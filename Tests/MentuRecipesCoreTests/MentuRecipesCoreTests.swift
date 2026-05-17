import XCTest
@testable import MentuRecipesCore

final class MentuRecipesCoreTests: XCTestCase {
    func testPromptRendering() {
        let rendered = PromptRenderer.render("Hello $NAME from ${PLACE}", vars: ["NAME": "Mentu", "PLACE": "recipes"])
        XCTAssertEqual(rendered, "Hello Mentu from recipes")
    }

    func testRecipeDiscoveryAndValidation() throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mentu/recipes"), withIntermediateDirectories: true)
        let recipeURL = root.appendingPathComponent(".mentu/recipes/demo.json")
        try """
        {"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"echo ok"}]}
        """.write(to: recipeURL, atomically: true, encoding: .utf8)

        let store = RecipeStore(paths: RecipePaths(workspace: root, home: root))
        let (recipe, url) = try store.load("demo")
        XCTAssertEqual(recipe.name, "demo")
        XCTAssertEqual(url.path, recipeURL.path)
    }

    func testRecipeFilesStayInRecipeRoots() throws {
        let root = try tempDir()
        let recipeURL = root.appendingPathComponent("outside.json")
        try """
        {"name":"outside","steps":[{"label":"one","backend":"shell","prompt":"echo no"}]}
        """.write(to: recipeURL, atomically: true, encoding: .utf8)
        let paths = RecipePaths(workspace: root, home: root)
        XCTAssertNil(paths.resolveRecipe(recipeURL.path))
    }

    func testDependencyCycleFails() throws {
        let steps = [
            RecipeStep(label: "a", backend: "shell", model: nil, prompt: "echo a", promptFile: nil, dir: nil, env: nil, timeout: nil, completionKeyword: nil, dependsOn: ["b"], maxRetries: nil, retryBackoffMs: nil, maxOutputBytes: nil, reasoning: nil, maxOutputTokens: nil, verify: nil),
            RecipeStep(label: "b", backend: "shell", model: nil, prompt: "echo b", promptFile: nil, dir: nil, env: nil, timeout: nil, completionKeyword: nil, dependsOn: ["a"], maxRetries: nil, retryBackoffMs: nil, maxOutputBytes: nil, reasoning: nil, maxOutputTokens: nil, verify: nil)
        ]
        let store = RecipeStore(paths: RecipePaths(workspace: try tempDir()))
        XCTAssertThrowsError(try store.topologicalOrder(steps))
    }

    func testPromptFilesStayInPromptRoots() throws {
        let root = try tempDir()
        let secret = root.appendingPathComponent("secret.txt")
        try "do-not-read".write(to: secret, atomically: true, encoding: .utf8)
        let paths = RecipePaths(workspace: root, home: root)
        XCTAssertNil(paths.resolvePrompt("../secret.txt"))
        XCTAssertNil(paths.resolvePrompt(secret.path))
    }

    func testPromptSymlinksCannotEscapePromptRoots() throws {
        let root = try tempDir()
        let prompts = root.appendingPathComponent(".mentu/prompts")
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)
        let secret = root.appendingPathComponent("secret.txt")
        try "do-not-read".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: prompts.appendingPathComponent("linked.md"),
            withDestinationURL: secret
        )
        let paths = RecipePaths(workspace: root, home: root)
        XCTAssertNil(paths.resolvePrompt("linked.md"))
    }

    func testUnsafeStepLabelFailsValidation() throws {
        let recipe = RecipeDefinition(
            name: "bad-label",
            steps: [
                RecipeStep(label: "../escape", backend: "shell", model: nil, prompt: "echo bad", promptFile: nil, dir: nil, env: nil, timeout: nil, completionKeyword: nil, dependsOn: nil, maxRetries: nil, retryBackoffMs: nil, maxOutputBytes: nil, reasoning: nil, maxOutputTokens: nil, verify: nil)
            ]
        )
        let store = RecipeStore(paths: RecipePaths(workspace: try tempDir()))
        XCTAssertThrowsError(try store.validate(recipe))
    }

    func testShellRecipeRunsOffline() async throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mentu/recipes"), withIntermediateDirectories: true)
        try """
        {
          "name": "shell-test",
          "steps": [
            {
              "label": "one",
              "backend": "shell",
              "prompt": "echo SHELL_TEST_COMPLETE",
              "completion_keyword": "SHELL_TEST_COMPLETE",
              "timeout": 5
            }
          ]
        }
        """.write(to: root.appendingPathComponent(".mentu/recipes/shell-test.json"), atomically: true, encoding: .utf8)

        let runner = RecipeRunner(options: RunOptions(workspace: root, home: root, cloudEnabled: false, quiet: true))
        let result = try await runner.run("shell-test")
        XCTAssertEqual(result.outcome, "ok")
        XCTAssertEqual(result.steps.first?.localComplete, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mentu/runs/\(result.runId)/run.json").path))
    }

    func testStepDirCannotEscapeWorkspace() async throws {
        let root = try tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".mentu/recipes"), withIntermediateDirectories: true)
        try """
        {
          "name": "dir-escape",
          "steps": [
            {
              "label": "one",
              "backend": "shell",
              "dir": "../",
              "prompt": "echo should-not-run"
            }
          ]
        }
        """.write(to: root.appendingPathComponent(".mentu/recipes/dir-escape.json"), atomically: true, encoding: .utf8)

        let runner = RecipeRunner(options: RunOptions(workspace: root, home: root, cloudEnabled: false, quiet: true))
        let result = try await runner.run("dir-escape")
        XCTAssertEqual(result.outcome, "failed")
        XCTAssertEqual(result.steps.first?.attempts, 0)
    }

    func testCredentialEnvAliases() {
        XCTAssertTrue(CredentialResolver.keychainCandidates(for: "OPENAI_API_KEY").contains("openai-api-key"))
        XCTAssertTrue(CredentialResolver.keychainCandidates(for: "DEEPSEEK_API_KEY").contains("deepseek-api-key"))
        XCTAssertTrue(CredentialResolver.keychainCandidates(for: "MENTU_API_KEY").contains("mentu-api-key"))
    }

    func testAdapterRegistryMetadata() {
        XCTAssertEqual(AdapterRegistry.adapter(named: "shell")?.completionPolicy, .shellExitCode)
        XCTAssertEqual(AdapterRegistry.adapter(named: "openai")?.executionKind, "llm-http")
        XCTAssertEqual(AdapterRegistry.adapter(named: "deepseek")?.executionKind, "llm-http")
        XCTAssertEqual(AdapterRegistry.adapter(named: "claude")?.executionKind, "agent-cli")
    }

    func testClaudeAgentEnvironmentDoesNotInheritOtherProviderSecrets() {
        let sanitized = ClaudeCLIAdapter.agentEnvironment(from: [
            "PATH": "/usr/bin",
            "HOME": "/tmp/home",
            "OPENAI_API_KEY": "sk-test",
            "DEEPSEEK_API_KEY": "deepseek-test",
            "CLAUDE_CODE_OAUTH_TOKEN": "claude-token",
            "ANTHROPIC_API_KEY": "anthropic-key"
        ])
        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
        XCTAssertEqual(sanitized["ANTHROPIC_API_KEY"], "anthropic-key")
        XCTAssertNil(sanitized["OPENAI_API_KEY"])
        XCTAssertNil(sanitized["DEEPSEEK_API_KEY"])
        XCTAssertNil(sanitized["CLAUDE_CODE_OAUTH_TOKEN"])
    }

    func testProviderCredentialsCannotBeSentToUnexpectedHosts() async throws {
        let adapter = OpenAIChatAdapter(
            name: "evil",
            baseURL: "https://example.com/v1",
            apiKeyEnv: "OPENAI_API_KEY",
            apiKeyVault: nil,
            defaultModel: "gpt-test",
            requiresAuth: true
        )
        do {
            _ = try await adapter.execute(
                AdapterRequest(
                    prompt: "hello",
                    systemContext: nil,
                    model: nil,
                    env: ["OPENAI_API_KEY": "sk-test-secret"],
                    timeout: 1,
                    maxOutputBytes: 1024,
                    reasoning: nil,
                    maxOutputTokens: nil,
                    workingDirectory: try tempDir()
                ),
                eventSink: { _ in }
            )
            XCTFail("Expected provider credential policy failure")
        } catch {
            XCTAssertTrue(String(describing: error).contains("cannot send OpenAI credentials"))
        }
    }

    func testReleaseScannerFindsProtectedContent() throws {
        let root = try tempDir()
        let file = root.appendingPathComponent("bad.txt")
        let localPath = ["/Users", "rashid", "Desktop"].joined(separator: "/")
        let protected = ["Sub", "trace"].joined()
        try "hello \(localPath)/\(protected)".write(to: file, atomically: true, encoding: .utf8)
        let findings = ReleaseScanner.scan(root: root)
        XCTAssertFalse(findings.isEmpty)
    }

    func testReleaseScannerFindsProtectedPaths() throws {
        let root = try tempDir()
        let protectedDir = root
            .appendingPathComponent(".mentu")
            .appendingPathComponent(["c", "ir"].joined())
            .appendingPathComponent("signals")
        try FileManager.default.createDirectory(at: protectedDir, withIntermediateDirectories: true)
        let file = protectedDir.appendingPathComponent("signal.json")
        try #"{"ok":true}"#.write(to: file, atomically: true, encoding: .utf8)
        let findings = ReleaseScanner.scan(root: root)
        XCTAssertTrue(findings.contains { $0.reason == "protected internal path" })
    }

    func testMockCloudClient() async throws {
        MockURLProtocol.responses = [
            "/v1/recipes/runs/start": #"{"runId":"cloud-run","windowStart":"2026-01-01T00:00:00Z"}"#,
            "/v1/recipes/evaluate-step": #"{"complete":true,"trust_score":0.91,"trust_mode":"MONITORED","flags":[],"recommendation":"advance"}"#,
            "/v1/recipes/runs/end": #"{"runId":"cloud-run","status":"updated"}"#
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = MentuCloudClient(baseURL: URL(string: "https://api.test")!, apiKey: "mk_test", session: session)

        let start = try await client.startRun(recipeName: "demo", workspaceID: "w")
        XCTAssertEqual(start.runId, "cloud-run")
        let verdict = try await client.evaluateStep(.init(run_id: start.runId, recipe_name: "demo", step_label: "one", backend: "shell", model: nil, exit_code: 0, local_complete: true, output_tail: "ok", duration_seconds: 1))
        XCTAssertEqual(verdict.complete, true)
        XCTAssertEqual(verdict.trust_score, 0.91)
        let end = try await client.endRun(runId: start.runId, outcome: "ok")
        XCTAssertEqual(end.status, "updated")
    }

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mentu-recipes-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class MockURLProtocol: URLProtocol {
    static var responses: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body = Self.responses[path] ?? "{}"
        let data = Data(body.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
