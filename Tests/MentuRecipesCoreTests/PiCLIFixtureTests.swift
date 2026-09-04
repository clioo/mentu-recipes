import XCTest
@testable import MentuRecipesCore

final class PiCLIFixtureTests: XCTestCase {
    private var roots: [URL] = []
    private var servers: [(Process, XCTestExpectation)] = []
    override func tearDown() async throws {
        for (process, exited) in servers {
            if process.isRunning { process.terminate() }
            await fulfillment(of: [exited], timeout: 5)
        }
        for root in roots { try FileManager.default.removeItem(at: root) }
    }

    private func fixture(mode: String) async throws -> (URL, Process, ProviderConfig) {
        guard ProcessRunner.findExecutable("pi") != nil, let node = ProcessRunner.findExecutable("node") else {
            throw XCTSkip("Install Pi 0.84.1+ and Node 22.19+ to exercise the real CLI against a deterministic provider")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mentu-real-pi-fixture-\(UUID().uuidString)")
        roots.append(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "runtime-proof-98413".write(to: root.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
        let serverURL = root.appendingPathComponent("server.mjs")
        try #"""
        import http from 'node:http';
        import fs from 'node:fs';
        const mode = process.argv[2];
        const requests = [];
        const server = http.createServer(async (req, res) => {
          let text = ''; for await (const part of req) text += part;
          const body = JSON.parse(text); requests.push(body);
          fs.writeFileSync('requests.json', JSON.stringify(requests));
          if (mode === 'failure') { res.writeHead(503); res.end(); return; }
          if (mode === 'skill' && !JSON.stringify(body).includes('fixture-proof-skill')) {
            res.writeHead(400); res.end('explicit skill missing'); return;
          }
          const tools = body.tools?.map(tool => tool.function.name) ?? [];
          if (mode === 'write' ? !tools.includes('write') : tools.includes('write')) {
            res.writeHead(400); res.end('unexpected tool policy'); return;
          }
          res.writeHead(200, { 'Content-Type': 'text/event-stream' });
          const chunk = (delta, finish = null) => res.write('data: ' + JSON.stringify({ id: 'fixture-completion',
            object: 'chat.completion.chunk', created: 1, model: 'fixture-model',
            choices: [{ index: 0, delta, finish_reason: finish }] }) + '\n\n');
          if (requests.length === 1) {
            const args = mode === 'write' ? { path: 'written.txt', content: 'runtime-write-proof' } : { path: 'fixture.txt' };
            chunk({ role: 'assistant', tool_calls: [{ index: 0, id: 'fixture-call', type: 'function',
              function: { name: mode === 'write' ? 'write' : 'read', arguments: JSON.stringify(args) } }] });
            chunk({}, 'tool_calls');
          } else {
            const proof = mode === 'write' ? fs.existsSync('written.txt') : JSON.stringify(body).includes('runtime-proof-98413');
            chunk({ role: 'assistant', content: proof ? 'Verified runtime-proof-98413' : 'MISSING PROOF' });
            chunk({}, 'stop');
          }
          res.write('data: ' + JSON.stringify({ id: 'fixture-usage', choices: [],
            usage: { prompt_tokens: 10, completion_tokens: 8, total_tokens: 18 } }) + '\n\n');
          res.end('data: [DONE]\n\n');
        });
        server.listen(0, '127.0.0.1', () => fs.writeFileSync('port.txt', String(server.address().port)));
        """#.write(to: serverURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [serverURL.path, mode]
        process.environment = PiCLIAdapter.runtimeEnvironment(ProcessInfo.processInfo.environment)
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = XCTestExpectation(description: "Fixture provider exits")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        servers.append((process, exited))
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("port.txt").path) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let port = try? String(contentsOf: root.appendingPathComponent("port.txt")) else {
            throw RecipeError.failed("Deterministic provider did not start")
        }
        var provider: [String: Any] = ["api": "pi", "base_url": "http://127.0.0.1:\(port)/v1",
            "api_key_env": "PI_FIXTURE_KEY", "model": "fixture-model", "max_tokens_field": "max_tokens"]
        if mode == "skill" {
            let skill = root.appendingPathComponent("fixture-proof-skill/SKILL.md")
            try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "---\nname: fixture-proof-skill\ndescription: Verify a fixture by reading its contents.\n---\nRead fixture.txt.\n"
                .write(to: skill, atomically: true, encoding: .utf8)
            provider["skills"] = [skill.path]
        }
        let configData = try JSONSerialization.data(withJSONObject: provider)
        return (root, process, try JSONDecoder().decode(ProviderConfig.self, from: configData))
    }

    private func run(mode: String) async throws -> (AdapterResult, URL) {
        let (root, _, config) = try await fixture(mode: mode)
        var env = ProcessInfo.processInfo.environment
        env["PI_FIXTURE_KEY"] = "local-fixture"
        let limits = InferenceBudget(maxRequests: 2, maxRequestBytes: 32768, maxTotalInputBytes: 65536,
                                     maxOutputTokens: 128, maxDurationSeconds: 30)
        let result = try await PiCLIAdapter(name: "fixture", config: config).execute(
            AdapterRequest(prompt: "Read fixture.txt and confirm its exact contents.", model: "fixture-model",
                env: env, timeout: 20, maxOutputBytes: 100_000, maxOutputTokens: 128,
                allowedTools: mode == "write" ? ["read", "write"] : ["read"], workingDirectory: root,
                inferenceBudget: InferenceBudgetContext(limits: limits, directory: root.appendingPathComponent("budget"))),
            eventSink: { _ in })
        return (result, root)
    }

    func testRealPiReadsFixtureThroughBoundedTransport() async throws {
        let (result, root) = try await run(mode: "read")
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.providerCompleted, result.stdout + result.stderr)
        XCTAssertTrue(result.stdout.contains("runtime-proof-98413"), result.stdout + result.stderr)
        XCTAssertEqual(result.inputTokens, 20)
        XCTAssertEqual(result.outputTokens, 16)
        let requests = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("requests.json"))) as? [[String: Any]]
        XCTAssertEqual(requests?.count, 2)
        XCTAssertTrue(requests?.allSatisfy { $0["max_tokens"] as? Int == 128 } == true)
    }

    func testRealPiCanUseExplicitlyAllowedWriteTool() async throws {
        let (result, root) = try await run(mode: "write")
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("written.txt")), "runtime-write-proof")
    }

    func testRealPiDoesNotAutomaticallyRetryProviderFailure() async throws {
        let (result, root) = try await run(mode: "failure")
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.providerCompleted)
        let requests = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("requests.json"))) as? [[String: Any]]
        XCTAssertEqual(requests?.count, 1)
    }

    func testRealPiLoadsOnlyExplicitlyConfiguredSkill() async throws {
        let (result, _) = try await run(mode: "skill")
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.providerCompleted)
    }

    func testChildRecipesAndResumeShareOriginalRequestBudget() async throws {
        let (root, _, config) = try await fixture(mode: "read")
        let recipeDir = root.appendingPathComponent(".mentu/recipes")
        try FileManager.default.createDirectory(at: recipeDir, withIntermediateDirectories: true)
        let child: [String: Any] = ["name": "child", "env": ["PI_FIXTURE_KEY": "local-fixture"],
            "providers": ["fixture": try JSONSerialization.jsonObject(with: JSONEncoder().encode(config))],
            "steps": [["label": "read", "backend": "fixture", "model": "fixture-model",
                       "prompt": "Read fixture.txt and confirm its exact contents.", "allowed_tools": ["read"], "timeout": 20]]]
        let limits = InferenceBudget(maxRequests: 2, maxRequestBytes: 32768, maxTotalInputBytes: 65536,
                                     maxOutputTokens: 128, maxDurationSeconds: 30)
        var parent: [String: Any] = ["name": "parent", "type": "pipeline", "steps": [],
            "inference_budget": try JSONSerialization.jsonObject(with: JSONEncoder().encode(limits)),
            "recipes": [["label": "one", "recipe": "child"], ["label": "two", "recipe": "child"]]]
        try JSONSerialization.data(withJSONObject: child).write(to: recipeDir.appendingPathComponent("child.json"))
        try JSONSerialization.data(withJSONObject: parent).write(to: recipeDir.appendingPathComponent("parent.json"))
        let runner = RecipeRunner(options: RunOptions(workspace: root, home: root, quiet: true))
        let first = try await runner.run("parent")
        XCTAssertEqual(first.outcome, "failed")
        XCTAssertEqual(first.inferenceBudget?.limits.maxRequests, 2)
        let resumed = try await runner.resume(runId: first.runId)
        XCTAssertEqual(resumed.outcome, "failed")
        XCTAssertEqual(resumed.inferenceBudget, first.inferenceBudget)
        let requests = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("requests.json"))) as? [[String: Any]]
        XCTAssertEqual(requests?.count, 2)
        let budgetFile = try XCTUnwrap(first.inferenceBudget?.directory.appendingPathComponent("budget.json"))
        let budgetState = try JSONSerialization.jsonObject(with: Data(contentsOf: budgetFile)) as? [String: Any]
        XCTAssertEqual(budgetState?["requests"] as? Int, 2)
        var changed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(limits)) as! [String: Any]
        changed["max_requests"] = 3
        parent["inference_budget"] = changed
        try JSONSerialization.data(withJSONObject: parent).write(to: recipeDir.appendingPathComponent("parent.json"))
        do {
            _ = try await runner.resume(runId: first.runId)
            XCTFail("Recovery must not reset the approved budget")
        } catch { XCTAssertTrue(String(describing: error).contains("original inference budget")) }
        parent["inference_budget"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(limits))
        try JSONSerialization.data(withJSONObject: parent).write(to: recipeDir.appendingPathComponent("parent.json"))
        try FileManager.default.removeItem(at: budgetFile.deletingLastPathComponent())
        do {
            _ = try await runner.resume(runId: first.runId)
            XCTFail("Recovery must not recreate deleted counters")
        } catch { XCTAssertTrue(String(describing: error).contains("original inference budget evidence")) }
    }
}
