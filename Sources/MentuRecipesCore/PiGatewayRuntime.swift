import Foundation

enum PiGatewayRuntime {
    static let source = #"""
    import http from 'node:http';
    import { randomBytes } from 'node:crypto';
    import { openBudget } from './budget.mjs';

    export function validateTarget(config) {
      const target = new URL(config.base_url);
      if (!['http:', 'https:'].includes(target.protocol) || target.username || target.password ||
          target.search || target.hash || !config.model || typeof config.model !== 'string') {
        throw new Error('Pi requires an explicit HTTP(S) target and exact model ID');
      }
      if (!['max_tokens', 'max_completion_tokens'].includes(config.max_tokens_field)) {
        throw new Error('Unsupported Chat Completions output token field');
      }
      return new URL(target.href.replace(/\/$/, '') + '/chat/completions');
    }

    export async function startGateway(config, apiKey) {
      const target = validateTarget(config);
      const budget = openBudget(config.budget_directory, config.limits,
        { endpoint: target.href, model: config.model, token_field: config.max_tokens_field }, config.started_at_ms);
      if (Date.now() >= budget.snapshot().deadline_ms) throw new Error('Budget deadline exceeded before Pi launch');
      const token = randomBytes(32).toString('hex');
      const controllers = new Set();
      let failed = false;
      const receipts = [];
      const server = http.createServer(async (request, response) => {
        let reservation;
        let responseBytes = 0;
        let usage;
        let pending = '';
        let sawDone = false;
        const controller = new AbortController();
        let timer;
        const fail = message => {
          failed = true;
          if (!response.headersSent) {
            response.writeHead(400, { 'Content-Type': 'application/json' });
            response.end(JSON.stringify({ error: { message } }));
          } else response.destroy();
        };
        try {
          if (request.headers.authorization !== 'Bearer ' + token) {
            response.writeHead(401); response.end(); return;
          }
          if (request.method !== 'POST' || request.url !== '/v1/chat/completions') {
            throw new Error('Only the configured Chat Completions route is allowed');
          }
          let size = 0;
          const chunks = [];
          for await (const chunk of request) {
            size += chunk.length;
            if (size > config.limits.max_request_bytes) throw new Error('Inference request body exceeds its byte limit');
            chunks.push(chunk);
          }
          const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          if (body.model !== config.model || (body.n !== undefined && body.n !== 1) || body.best_of !== undefined) {
            throw new Error('Model or completion multiplicity differs from the approved target');
          }
          if (body.stream !== true) throw new Error('Pi transport requires streaming Chat Completions');
          const tokenFields = ['max_tokens', 'max_completion_tokens', 'max_output_tokens'];
          const supplied = tokenFields.filter(field => body[field] !== undefined).map(field => body[field]);
          if (supplied.some(value => !Number.isSafeInteger(value) || value < 1)) throw new Error('Invalid output token limit');
          const cap = Math.min(config.max_output_tokens, config.limits.max_output_tokens, ...supplied);
          for (const field of tokenFields) delete body[field];
          body[config.max_tokens_field] = cap;
          const serialized = JSON.stringify(body);
          reservation = budget.reserve(Buffer.byteLength(serialized), cap);
          receipts.push({ id: reservation.id, usage: null });
          controllers.add(controller);
          timer = setTimeout(() => controller.abort(), Math.max(1, Math.min(
            reservation.deadline - Date.now(), config.request_timeout_ms)));
          response.on('close', () => { if (!response.writableEnded) controller.abort(); });
          const upstream = await fetch(target, { method: 'POST', redirect: 'manual', signal: controller.signal,
            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + apiKey }, body: serialized });
          if (!upstream.ok) throw new Error('Configured provider returned HTTP ' + upstream.status);
          if (!upstream.headers.get('content-type')?.includes('text/event-stream')) {
            throw new Error('Configured provider did not return an event stream');
          }
          response.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
          const decoder = new TextDecoder();
          for await (const chunk of upstream.body) {
            responseBytes += chunk.length;
            if (responseBytes > config.max_response_bytes) throw new Error('Provider response byte limit exceeded');
            pending += decoder.decode(chunk, { stream: true });
            let newline;
            while ((newline = pending.indexOf('\n')) !== -1) {
              const line = pending.slice(0, newline).trim();
              pending = pending.slice(newline + 1);
              if (line === 'data: [DONE]') sawDone = true;
              else if (line.startsWith('data: ')) {
                const item = JSON.parse(line.slice(6));
                if (item.error) throw new Error('Provider reported a streaming error');
                if (item.usage) {
                  const input = item.usage.prompt_tokens, output = item.usage.completion_tokens;
                  if (Number.isSafeInteger(input) && input >= 0 && Number.isSafeInteger(output) && output >= 0) {
                    usage = { input_tokens: input, output_tokens: output };
                  }
                }
              }
            }
            if (!response.write(chunk)) await new Promise((resolve, reject) => {
              const cleanup = () => { response.off('drain', drained); response.off('close', closed); };
              const drained = () => { cleanup(); resolve(); };
              const closed = () => { cleanup(); reject(new Error('Pi disconnected')); };
              response.once('drain', drained); response.once('close', closed);
            });
          }
          if (!sawDone) throw new Error('Provider stream ended without its completion marker');
          if (usage && usage.output_tokens > cap) throw new Error('Provider exceeded the requested output token cap');
          budget.finish(reservation.id, { status: upstream.status, response_bytes: responseBytes, usage: usage ?? null });
          receipts.find(item => item.id === reservation.id).usage = usage ?? null;
          reservation = undefined;
          response.end();
        } catch (error) {
          const message = error.name === 'AbortError' ? 'Inference request deadline exceeded' : error.message;
          if (reservation) {
            try { budget.finish(reservation.id, { error: message, response_bytes: responseBytes, usage: usage ?? null }); }
            catch { /* An uncertain reservation remains charged and in flight. */ }
          }
          fail(message);
        } finally { clearTimeout(timer); controllers.delete(controller); }
      });
      server.requestTimeout = Math.min(config.request_timeout_ms, 60000);
      server.headersTimeout = Math.min(config.request_timeout_ms, 15000);
      await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
      return { baseURL: 'http://127.0.0.1:' + server.address().port + '/v1', token, budget,
        receipts: () => receipts,
        failed: () => failed,
        async close() {
          for (const controller of controllers) controller.abort();
          server.closeAllConnections();
          await new Promise(resolve => server.close(resolve));
        }
      };
    }
    """#
}
