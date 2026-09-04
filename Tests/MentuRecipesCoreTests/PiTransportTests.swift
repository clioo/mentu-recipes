import XCTest
@testable import MentuRecipesCore

final class PiTransportTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDownWithError() throws {
        for root in roots { try FileManager.default.removeItem(at: root) }
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mentu-pi-test-\(UUID().uuidString)")
        roots.append(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try PiCLIAdapter.writeRuntime(to: root)
        return root
    }

    private func nodeTest(_ source: String) async throws {
        guard let node = ProcessRunner.findExecutable("node") else { throw XCTSkip("Node.js is required for bounded Pi transport tests") }
        let root = try workspace()
        let script = root.appendingPathComponent("test.mjs")
        try source.write(to: script, atomically: true, encoding: .utf8)
        let result = try await ProcessRunner.run(executable: node, arguments: [script.path],
            env: PiCLIAdapter.runtimeEnvironment(ProcessInfo.processInfo.environment), workingDirectory: root,
            timeout: 10, maxOutputBytes: 100_000, eventSink: { _ in })
        XCTAssertEqual(result.exitCode, 0, result.stdout + result.stderr)
    }

    func testBudgetPersistsCountersPolicyDeadlineAndUnknownReservations() async throws {
        try await nodeTest(#"""
        import assert from 'node:assert/strict';
        import { openBudget } from './budget.mjs';
        const limits = { max_requests: 2, max_concurrent_requests: 1, max_request_bytes: 100,
          max_total_input_bytes: 150, max_output_tokens: 10, max_duration_seconds: 60 };
        const identity = { endpoint: 'http://127.0.0.1/v1/chat/completions', model: 'fixture' };
        const first = openBudget('./state', limits, identity);
        const deadline = first.snapshot().deadline_ms;
        const reservation = first.reserve(50, 10);
        assert.throws(() => first.reserve(1, 1), /concurrency/);
        const reopened = openBudget('./state', limits, identity, Date.now() + 600000);
        assert.equal(reopened.snapshot().requests, 1);
        assert.equal(reopened.snapshot().deadline_ms, deadline);
        assert.throws(() => reopened.reserve(1, 1), /unverifiable/);
        assert.throws(() => openBudget('./state', { ...limits, max_requests: 9 }, identity), /policy changed/);
        assert.throws(() => openBudget('./state', limits, { ...identity, model: 'other' }), /policy changed/);
        reopened.finish(reservation.id, { status: 200 });
        assert.throws(() => reopened.reserve(101, 1), /byte limit/);
        assert.throws(() => reopened.reserve(20, 11), /output token/);
        const second = reopened.reserve(100, 10);
        reopened.finish(second.id, { status: 200 });
        assert.equal(reopened.snapshot().requests, 2);
        assert.equal(reopened.snapshot().input_bytes, 150);
        assert.throws(() => reopened.reserve(1, 1), /request limit/);
        """#)
    }

    func testGatewayEnforcesActualBodyAndCountsEachForwardedRequest() async throws {
        try await nodeTest(#"""
        import assert from 'node:assert/strict';
        import http from 'node:http';
        import { startGateway } from './gateway.mjs';
        const seen = [];
        const upstream = http.createServer(async (req, res) => {
          let raw = ''; for await (const chunk of req) raw += chunk;
          seen.push({ body: JSON.parse(raw), auth: req.headers.authorization });
          res.writeHead(200, { 'Content-Type': 'text/event-stream' });
          res.end('data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":1}}\n\ndata: [DONE]\n\n');
        });
        await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
        const limits = { max_requests: 2, max_concurrent_requests: 1, max_request_bytes: 1024,
          max_total_input_bytes: 2048, max_output_tokens: 8, max_duration_seconds: 60 };
        const config = { base_url: 'http://127.0.0.1:' + upstream.address().port + '/v1', model: 'fixture',
          max_tokens_field: 'max_tokens', limits, budget_directory: './state', max_output_tokens: 4,
          request_timeout_ms: 1000, max_response_bytes: 10000 };
        const gateway = await startGateway(config, 'fixture-key');
        async function request(body) {
          const response = await fetch(gateway.baseURL + '/chat/completions', { method: 'POST',
            headers: { Authorization: 'Bearer ' + gateway.token, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'fixture', stream: true, messages: [], ...body }) });
          await response.text(); return response.status;
        }
        try {
          assert.equal(await request({ model: 'unapproved' }), 400);
          assert.equal(await request({ messages: [{ role: 'user', content: 'x'.repeat(2000) }] }), 400);
          assert.equal(seen.length, 0);
          assert.equal(await request({ max_completion_tokens: 999, max_output_tokens: 999 }), 200);
          assert.equal(seen[0].body.max_tokens, 4);
          assert.equal(seen[0].body.max_completion_tokens, undefined);
          assert.equal(seen[0].body.max_output_tokens, undefined);
          assert.equal(seen[0].auth, 'Bearer fixture-key');
          assert.equal(await request({ max_tokens: 1 }), 200);
          assert.equal(seen[1].body.max_tokens, 1);
          assert.equal(await request({}), 400);
          assert.equal(seen.length, 2);
          assert.equal(gateway.budget.snapshot().requests, 2);
          assert.equal(gateway.receipts()[0].usage.input_tokens, 10);
        } finally {
          await gateway.close(); upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
        }
        """#)
    }

    func testProviderFailureStopsBudgetWithoutRetryOrFallback() async throws {
        try await nodeTest(#"""
        import assert from 'node:assert/strict';
        import http from 'node:http';
        import { startGateway } from './gateway.mjs';
        let calls = 0;
        const upstream = http.createServer((req, res) => { calls++; res.writeHead(503); res.end('unavailable'); });
        await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
        const config = { base_url: 'http://127.0.0.1:' + upstream.address().port + '/v1', model: 'fixture',
          max_tokens_field: 'max_completion_tokens', budget_directory: './state', max_output_tokens: 4,
          request_timeout_ms: 1000, max_response_bytes: 10000,
          limits: { max_requests: 4, max_concurrent_requests: 1, max_request_bytes: 1024,
            max_total_input_bytes: 4096, max_output_tokens: 4, max_duration_seconds: 60 } };
        const gateway = await startGateway(config, 'fixture-key');
        try {
          for (let i = 0; i < 2; i++) {
            const response = await fetch(gateway.baseURL + '/chat/completions', { method: 'POST',
              headers: { Authorization: 'Bearer ' + gateway.token, 'Content-Type': 'application/json' },
              body: JSON.stringify({ model: 'fixture', stream: true, messages: [] }) });
            assert.equal(response.status, 400); await response.text();
          }
          assert.equal(calls, 1);
          assert.equal(gateway.budget.snapshot().requests, 1);
          assert.match(gateway.budget.snapshot().stop_reason, /HTTP 503/);
        } finally {
          await gateway.close(); upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
        }
        """#)
    }

    func testPiParserRequiresFinalProviderCompletionNotJustAgentEnd() {
        var parser = PiJSONParser()
        XCTAssertEqual(parser.parse(#"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"OK"}}"# + "\n"), ["OK"])
        _ = parser.parse(#"{"type":"tool_execution_start","toolName":"read"}"# + "\n")
        _ = parser.parse(#"{"type":"agent_end","messages":[{"role":"assistant","stopReason":"length"}]}"# + "\n")
        XCTAssertTrue(parser.failed)
        XCTAssertFalse(parser.completed)
        XCTAssertEqual(parser.toolCalls, ["read"])
        var complete = PiJSONParser()
        _ = complete.parse(#"{"type":"agent_end","messages":[{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"done"}]}]}"#)
        complete.finish()
        XCTAssertTrue(complete.completed)
        XCTAssertFalse(complete.failed)
        XCTAssertEqual(complete.text, "done")
    }

    func testPiIsOptInAndDoesNotInheritForeignCredentials() {
        let adapter = AdapterRegistry.adapter(named: "pi")
        XCTAssertNotNil(adapter)
        XCTAssertEqual(adapter?.isAutoDetectable, false)
        XCTAssertEqual(adapter?.capabilities.supportsMaxOutputTokens, true)
        let env = PiCLIAdapter.runtimeEnvironment(["HOME": "/fixture", "PATH": "/bin", "OPENAI_API_KEY": "foreign",
            "ANTHROPIC_API_KEY": "foreign", "PI_CODING_AGENT_DIR": "/unreviewed", "NODE_OPTIONS": "unreviewed", "HTTP_PROXY": "unreviewed"])
        XCTAssertEqual(env, ["HOME": "/fixture", "PATH": "/bin"])
    }

    func testProcessTimeoutDoesNotWaitForUncancelledExitTask() async throws {
        let root = try workspace()
        let start = Date()
        let result = try await ProcessRunner.run(executable: "/bin/sleep", arguments: ["10"],
            env: ProcessInfo.processInfo.environment, workingDirectory: root, timeout: 1,
            maxOutputBytes: 1000, eventSink: { _ in })
        XCTAssertEqual(result.exitCode, 124)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testMissingBudgetEvidenceIsNotReinitialized() async throws {
        try await nodeTest(#"""
        import fs from 'node:fs';
        import assert from 'node:assert/strict';
        import { openBudget } from './budget.mjs';
        const limits = { max_requests: 2, max_concurrent_requests: 1, max_request_bytes: 100,
          max_total_input_bytes: 150, max_output_tokens: 10, max_duration_seconds: 60 };
        const budget = openBudget('./state', limits, { model: 'fixture' });
        budget.reserve(10, 10);
        fs.unlinkSync('./state/budget.json');
        assert.throws(() => openBudget('./state', limits, { model: 'fixture' }), /counters are missing/);
        assert.equal(fs.existsSync('./state/budget.json'), false);
        """#)
    }

    func testConcurrentProcessesCannotOverspendAndCorruptionFailsClosed() async throws {
        try await nodeTest(#"""
        import fs from 'node:fs';
        import assert from 'node:assert/strict';
        import { spawn } from 'node:child_process';
        import { openBudget } from './budget.mjs';
        const limits = { max_requests: 3, max_concurrent_requests: 1, max_request_bytes: 100,
          max_total_input_bytes: 300, max_output_tokens: 10, max_duration_seconds: 60 };
        const identity = { model: 'fixture' };
        const budget = openBudget('./state', limits, identity);
        const source = `import {openBudget} from './budget.mjs';
          try { const b = openBudget('./state', ${JSON.stringify(limits)}, ${JSON.stringify(identity)});
            const r = b.reserve(100, 10); b.finish(r.id, {status:200}); }
          catch { process.exitCode = 2; }`;
        const codes = await Promise.all(Array.from({length:12}, () => new Promise(resolve => {
          const child = spawn(process.execPath, ['--input-type=module', '-e', source], {stdio:'ignore'});
          child.once('exit', resolve);
        })));
        const snapshot = budget.snapshot();
        assert.ok(snapshot.requests > 0 && snapshot.requests <= 3);
        assert.ok(snapshot.requests >= codes.filter(code => code === 0).length);
        assert.equal(snapshot.input_bytes, snapshot.requests * 100);
        assert.ok(Object.keys(snapshot.inflight).length <= 1);
        snapshot.requests = 0;
        fs.writeFileSync('./state/budget.json', JSON.stringify(snapshot));
        assert.throws(() => budget.snapshot(), /inconsistent/);
        """#)
    }

    func testExpiredBudgetRedirectAndTruncatedStreamNeverPass() async throws {
        try await nodeTest(#"""
        import assert from 'node:assert/strict';
        import http from 'node:http';
        import { startGateway } from './gateway.mjs';
        import { openBudget } from './budget.mjs';
        const limits = { max_requests: 2, max_concurrent_requests: 1, max_request_bytes: 1024,
          max_total_input_bytes: 2048, max_output_tokens: 8, max_duration_seconds: 1 };
        const expired = openBudget('./expired', limits, {model:'fixture'}, Date.now() - 2000);
        assert.throws(() => expired.reserve(10, 1), /deadline/);
        assert.equal(expired.snapshot().requests, 0);
        let calls = 0;
        let mode = 'redirect';
        const upstream = http.createServer(async (req, res) => {
          calls++;
          let raw = ''; for await (const chunk of req) raw += chunk;
          const body = JSON.parse(raw);
          assert.equal(body.max_completion_tokens, 4);
          assert.equal(body.max_tokens, undefined);
          if (mode === 'redirect') { res.writeHead(307, {Location:'/other'}); res.end(); }
          else {
            res.writeHead(200, {'Content-Type':'text/event-stream'});
            res.end('data: {"choices":[]}\n\n');
          }
        });
        await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
        try {
          for (mode of ['redirect', 'truncated']) {
            const gateway = await startGateway({base_url:'http://127.0.0.1:' + upstream.address().port + '/v1',
              model:'fixture', max_tokens_field:'max_completion_tokens', limits,
              budget_directory:'./' + mode, max_output_tokens:4, request_timeout_ms:1000,
              max_response_bytes:10000}, 'fixture');
            try {
              try {
                const response = await fetch(gateway.baseURL + '/chat/completions', {method:'POST',
                  headers:{Authorization:'Bearer ' + gateway.token},
                  body:JSON.stringify({model:'fixture',stream:true,messages:[]})});
                await response.text();
                assert.equal(response.status, 400);
              } catch (error) { assert.ok(error instanceof TypeError); }
              assert.equal(gateway.failed(), true);
              assert.equal(gateway.budget.snapshot().requests, 1);
              assert.ok(gateway.budget.snapshot().stop_reason);
            } finally { await gateway.close(); }
          }
          assert.equal(calls, 2);
        } finally { upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve)); }
        """#)
    }
}
