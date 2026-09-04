import Foundation

// Embedded so the existing single-binary distribution does not need a resource bundle.
enum PiBudgetRuntime {
    static let source = #"""
    import fs from 'node:fs';
    import path from 'node:path';
    import { createHash, randomUUID } from 'node:crypto';

    const canonical = value => JSON.stringify(value, Object.keys(value).sort());
    const hash = value => createHash('sha256').update(value).digest('hex');
    export function validateLimits(limits) {
      const fields = ['max_requests', 'max_concurrent_requests', 'max_request_bytes',
        'max_total_input_bytes', 'max_output_tokens', 'max_duration_seconds'];
      if (!limits || fields.some(key => !Number.isSafeInteger(limits[key]) || limits[key] < 1) ||
          limits.max_concurrent_requests > limits.max_requests ||
          limits.max_requests > 1000000 || limits.max_output_tokens > 2147483647 ||
          limits.max_duration_seconds > 604800 ||
          limits.max_request_bytes > 16777216 || limits.max_total_input_bytes < limits.max_request_bytes) {
        throw new Error('Invalid inference budget');
      }
    }

    function atomicJSON(file, value) {
      const temporary = file + '.' + randomUUID() + '.tmp';
      fs.writeFileSync(temporary, JSON.stringify(value, null, 2), { mode: 0o600, flag: 'wx', flush: true });
      fs.renameSync(temporary, file);
    }

    export function openBudget(directory, limits, identity, startedAt = Date.now()) {
      validateLimits(limits);
      fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
      directory = fs.realpathSync(directory);
      const lock = path.join(directory, 'budget.lock');
      const file = path.join(directory, 'budget.json');
      const marker = path.join(directory, 'budget-identity.json');
      const fingerprint = hash(canonical(limits) + '\n' + canonical(identity));
      function transaction(update) {
        try { fs.mkdirSync(lock, { mode: 0o700 }); }
        catch { throw new Error('Budget ownership is busy or unverifiable; no automatic takeover'); }
        try {
          let state;
          if (fs.existsSync(file)) {
            state = JSON.parse(fs.readFileSync(file, 'utf8'));
            if (state.version !== 1 || state.fingerprint !== fingerprint ||
                !Number.isSafeInteger(state.requests) || state.requests < 0 || state.requests > limits.max_requests ||
                !Number.isSafeInteger(state.input_bytes) || state.input_bytes < 0 || state.input_bytes > limits.max_total_input_bytes ||
                !Number.isSafeInteger(state.started_at_ms) || state.started_at_ms < 0 ||
                state.deadline_ms !== state.started_at_ms + limits.max_duration_seconds * 1000 ||
                !Array.isArray(state.events) ||
                !state.inflight || typeof state.inflight !== 'object' || Array.isArray(state.inflight)) {
              throw new Error('Budget evidence or policy changed; refusing to reset counters');
            }
            const birth = JSON.parse(fs.readFileSync(marker, 'utf8'));
            const reserved = state.events.filter(event => event.type === 'request_reserved');
            const finished = state.events.filter(event => event.type === 'request_finished');
            const ids = new Set(reserved.map(event => event.id));
            const done = new Set(finished.map(event => event.id));
            if (birth.fingerprint !== fingerprint || birth.started_at_ms !== state.started_at_ms ||
                reserved.length !== state.requests || ids.size !== reserved.length || done.size !== finished.length ||
                reserved.some((event, index) => event.request !== index + 1 ||
                  !Number.isSafeInteger(event.request_bytes) || event.request_bytes < 1) ||
                reserved.reduce((sum, event) => sum + event.request_bytes, 0) !== state.input_bytes ||
                finished.some(event => !ids.has(event.id)) ||
                Object.keys(state.inflight).length !== ids.size - done.size ||
                Object.keys(state.inflight).some(id => !ids.has(id) || done.has(id))) {
              throw new Error('Budget evidence is inconsistent; refusing to reset counters');
            }
          } else {
            if (fs.existsSync(marker)) throw new Error('Budget counters are missing; refusing to reset an initialized budget');
            const now = startedAt;
            if (!Number.isSafeInteger(now) || now < 0) throw new Error('Invalid budget start time');
            atomicJSON(marker, { version: 1, fingerprint, started_at_ms: now });
            state = { version: 1, fingerprint, limits, identity, started_at_ms: now,
              deadline_ms: now + limits.max_duration_seconds * 1000, requests: 0,
              input_bytes: 0, inflight: {}, events: [] };
          }
          const result = update(state);
          atomicJSON(file, state);
          return result;
        } finally { fs.rmdirSync(lock); }
      }
      transaction(() => {});
      return {
        snapshot: () => transaction(state => structuredClone(state)),
        reserve(bytes, outputTokens) {
          return transaction(state => {
            if (state.stop_reason) throw new Error('Budget stopped: ' + state.stop_reason);
            if (Date.now() >= state.deadline_ms) throw new Error('Budget deadline exceeded');
            if (state.requests >= limits.max_requests) throw new Error('Inference request limit exceeded');
            if (Object.keys(state.inflight).length >= limits.max_concurrent_requests) {
              throw new Error('Inference concurrency limit reached or earlier request is unverifiable');
            }
            if (!Number.isSafeInteger(bytes) || bytes < 1 || bytes > limits.max_request_bytes ||
                state.input_bytes + bytes > limits.max_total_input_bytes) throw new Error('Inference input byte limit exceeded');
            if (!Number.isSafeInteger(outputTokens) || outputTokens < 1 || outputTokens > limits.max_output_tokens) {
              throw new Error('Inference output token limit exceeded');
            }
            const id = randomUUID();
            state.requests += 1;
            state.input_bytes += bytes;
            state.inflight[id] = { request: state.requests, started_at_ms: Date.now(), request_bytes: bytes,
              output_token_limit: outputTokens };
            state.events.push({ type: 'request_reserved', id, ...state.inflight[id] });
            return { id, deadline: state.deadline_ms };
          });
        },
        finish(id, result) {
          transaction(state => {
            if (!state.inflight[id]) throw new Error('Unknown inference reservation');
            delete state.inflight[id];
            state.events.push({ type: 'request_finished', id, ended_at_ms: Date.now(), ...result });
            if (result.error) state.stop_reason = result.error;
          });
        }
      };
    }
    """#
}
