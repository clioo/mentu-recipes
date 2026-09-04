import XCTest
@testable import MentuRecipesCore

final class AdmissionTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try FileManager.default.removeItem(at: root) }
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mentu-admission-test-\(UUID().uuidString)")
        roots.append(root)
        for dir in [".mentu/recipes", ".mentu/prompts"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        return root
    }

    private func put(_ text: String, _ path: String, in root: URL) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    private func recipe(_ body: String, in root: URL, name: String = "demo") throws {
        try put(body, ".mentu/recipes/\(name).json", in: root)
    }

    private func options(_ root: URL, digest: String? = nil, key: String? = nil, vars: [String: String] = [:]) -> RunOptions {
        RunOptions(workspace: root, home: root, vars: vars, quiet: true, planDigest: digest, requestKey: key)
    }

    private func admitted(_ root: URL, key: String = "click-1") throws -> RunOptions {
        options(root, digest: try ExecutionPlan.resolve("demo", options: options(root)).digest, key: key)
    }

    private func expectFailure(_ operation: () async throws -> Void, contains: String) async {
        do { try await operation(); XCTFail("Expected failure: \(contains)") }
        catch { XCTAssertTrue(String(describing: error).contains(contains), "Unexpected error: \(error)") }
    }

    func testDigestStableAndReviewDoesNotSerializePromptOrEnvironmentSecrets() throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","env":{"PRIVATE":"private-test-value"},"steps":[{"label":"one","backend":"shell","prompt":"echo sensitive-prompt"}]}"#, in: root)
        let first = try ExecutionPlan.resolve("demo", options: options(root))
        let second = try ExecutionPlan.resolve("demo", options: options(root))
        XCTAssertEqual(first.digest, second.digest)
        let json = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
        XCTAssertFalse(json.contains("private-test-value"))
        XCTAssertFalse(json.contains("sensitive-prompt"))
        XCTAssertEqual(first.steps.first?.backend, "shell")
        XCTAssertNotEqual(first.digest, try ExecutionPlan.resolve("demo", options: options(root, vars: ["X": "changed"])).digest)
    }

    func testPromptChangeRefusesExecutionBeforeAnyHookOrRecord() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","hooks":{"before_run":["touch hook-ran"]},"steps":[{"label":"one","backend":"shell","prompt_file":"one.md"}]}"#, in: root)
        try put("echo approved", ".mentu/prompts/one.md", in: root)
        let approved = try admitted(root)
        try put("touch unapproved", ".mentu/prompts/one.md", in: root)
        await expectFailure({ _ = try await RecipeRunner(options: approved).run("demo") }, contains: "plan changed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hook-ran").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mentu/runs").path))
    }

    func testCapturedPromptIsNotRereadAfterExecutionStarts() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","hooks":{"before_run":["printf 'echo MUTATED' > .mentu/prompts/one.md"]},"steps":[{"label":"one","backend":"shell","prompt_file":"one.md"}]}"#, in: root)
        try put("echo APPROVED", ".mentu/prompts/one.md", in: root)
        let record = try await RecipeRunner(options: admitted(root)).run("demo")
        XCTAssertEqual(record.outcome, "ok")
        let output = try String(contentsOf: root.appendingPathComponent(".mentu/runs/\(record.runId)/one.stdout"))
        XCTAssertTrue(output.contains("APPROVED"))
        XCTAssertFalse(output.contains("MUTATED"))
    }

    func testBudgetedExecutionRetainsCapturedInputsAndBindsSuppliedBudget() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","inference_budget":{"max_requests":4,"max_concurrent_requests":1,"max_request_bytes":1024,"max_total_input_bytes":4096,"max_output_tokens":128,"max_duration_seconds":60},"hooks":{"before_run":["printf 'echo MUTATED' > .mentu/prompts/one.md"]},"steps":[{"label":"one","backend":"shell","prompt_file":"one.md"}]}"#, in: root)
        try put("echo APPROVED", ".mentu/prompts/one.md", in: root)
        let record = try await RecipeRunner(options: admitted(root)).run("demo")
        XCTAssertEqual(record.outcome, "ok")
        XCTAssertEqual(record.inferenceBudget?.limits.maxRequests, 4)
        let output = try String(contentsOf: root.appendingPathComponent(".mentu/runs/\(record.runId)/one.stdout"))
        XCTAssertTrue(output.contains("APPROVED"))
        XCTAssertFalse(output.contains("MUTATED"))
        let plain = try ExecutionPlan.resolve("demo", options: options(root))
        let supplied = try ExecutionPlan.resolve("demo", options: RunOptions(workspace: root, home: root,
            inferenceBudget: record.inferenceBudget))
        XCTAssertNotEqual(plain.digest, supplied.digest)
    }

    func testRepeatedIntentReturnsSameRunAcrossRunnerInstances() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"echo once >> count"}]}"#, in: root)
        let approved = try admitted(root)
        let first = try await RecipeRunner(options: approved).run("demo")
        let second = try await RecipeRunner(options: approved).run("demo")
        XCTAssertEqual(first.runId, second.runId)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("count")), "once\n")
        let conflicting = options(root, digest: try ExecutionPlan.resolve("demo", options: options(root, vars: ["NEW": "value"])).digest,
                                  key: "click-1", vars: ["NEW": "value"])
        await expectFailure({ _ = try await RecipeRunner(options: conflicting).run("demo") }, contains: "Request key")
    }

    func testMalformedAdmissionDoesNotFallBackToLegacy() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"touch ran"}]}"#, in: root)
        for option in [options(root, digest: "bad", key: "ok"), options(root, key: "alone"), options(root, digest: String(repeating: "a", count: 64))] {
            await expectFailure({ _ = try await RecipeRunner(options: option).run("demo") }, contains: "Admission requires")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ran").path))
    }

    func testWorkspaceLeaseIsIndependentOfIntentAndCanonicalizesSymlinks() throws {
        let root = try workspace()
        let other = try workspace()
        let lease = try WorkspaceAdmissionLease(workspace: root)
        let alias = other.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertThrowsError(try WorkspaceAdmissionLease(workspace: alias))
        let independent = try WorkspaceAdmissionLease(workspace: other)
        withExtendedLifetime((lease, independent)) {}
    }

    func testUnverifiableOwnerDoesNotGetSilentlyReplaced() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"touch ran"}]}"#, in: root)
        let approved = try admitted(root)
        do {
            let lease = try WorkspaceAdmissionLease(workspace: root)
            try WorkspaceAdmissionLease.write(AdmissionReceipt(version: 1, digest: approved.planDigest!, operation: "run",
                                                               runId: "run_orphan", requestHash: "old"),
                                               at: lease.directory.appendingPathComponent("active.json"))
        }
        await expectFailure({ _ = try await RecipeRunner(options: approved).run("demo") }, contains: "unverifiable")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ran").path))
    }

    func testResumeRequiresOriginalPlanAndPreservesAttempts() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"echo attempt; test -f allow"}]}"#, in: root)
        let approved = try admitted(root)
        let first = try await RecipeRunner(options: approved).run("demo")
        XCTAssertEqual(first.outcome, "failed")
        await expectFailure({ _ = try await RecipeRunner(options: self.options(root)).resume(runId: first.runId) }, contains: "Admission requires")
        try put("", "allow", in: root)
        let resumeOptions = options(root, digest: approved.planDigest, key: "resume-1")
        let resumed = try await RecipeRunner(options: resumeOptions).resume(runId: first.runId)
        XCTAssertEqual(resumed.outcome, "ok")
        XCTAssertEqual(resumed.steps.last?.attempts, 2)
        for attempt in [1, 2] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mentu/runs/\(first.runId)/one.attempt-\(attempt).stdout").path))
        }
        let repeated = try await RecipeRunner(options: resumeOptions).resume(runId: first.runId)
        XCTAssertEqual(repeated.steps.count, resumed.steps.count)
    }

    func testRecoveryChangeDoesNotMutateState() async throws {
        let root = try workspace()
        let original = #"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"exit 1"}]}"#
        try recipe(original, in: root)
        let approved = try admitted(root)
        let record = try await RecipeRunner(options: approved).run("demo")
        let stateURL = root.appendingPathComponent(".mentu/runs/\(record.runId)/state.json")
        let before = try Data(contentsOf: stateURL)
        try recipe(original.replacingOccurrences(of: "exit 1", with: "exit 0"), in: root)
        await expectFailure({
            _ = try await RecipeRunner(options: self.options(root, digest: approved.planDigest, key: "retry-1"))
                .resume(runId: record.runId, retryStep: "one")
        }, contains: "plan changed")
        XCTAssertEqual(try Data(contentsOf: stateURL), before)
    }

    func testChildRunIdentitySurvivesParentRecovery() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","type":"pipeline","steps":[],"recipes":[{"label":"child","recipe":"child"}]}"#, in: root)
        try recipe(#"{"name":"child","steps":[{"label":"done","backend":"shell","prompt":"echo once >> count"},{"label":"later","backend":"shell","prompt":"test -f allow"}]}"#, in: root, name: "child")
        let approved = try admitted(root)
        let first = try await RecipeRunner(options: approved).run("demo")
        XCTAssertEqual(first.outcome, "failed")
        let state = try RunStateStore.load(runDir: root.appendingPathComponent(".mentu/runs/\(first.runId)"))
        let firstSnapshot = await state.snapshot()
        let childID = try XCTUnwrap(firstSnapshot.childRunIds?["child"])
        try put("", "allow", in: root)
        let resumed = try await RecipeRunner(options: options(root, digest: approved.planDigest, key: "resume-parent"))
            .resume(runId: first.runId)
        XCTAssertEqual(resumed.outcome, "ok")
        let newState = try RunStateStore.load(runDir: root.appendingPathComponent(".mentu/runs/\(first.runId)"))
        let snapshot = await newState.snapshot()
        XCTAssertEqual(snapshot.childRunIds?["child"], childID)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("count")), "once\n")
    }

    func testRecursiveRecipesAndDuplicateNodeLabelsAreRejected() throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","type":"pipeline","steps":[],"recipes":[{"label":"self","recipe":"demo"}]}"#, in: root)
        XCTAssertThrowsError(try ExecutionPlan.resolve("demo", options: options(root)))
        try recipe(#"{"name":"demo","type":"pipeline","steps":[],"recipes":[{"label":"duplicate","recipe":"child"},{"label":"duplicate","recipe":"child"}]}"#, in: root)
        XCTAssertThrowsError(try ExecutionPlan.resolve("demo", options: options(root)))
    }

    func testAgentBackendAndModelMustBeExplicit() throws {
        let root = try workspace()
        for body in [#"{"name":"demo","steps":[{"label":"one","prompt":"anything"}]}"#,
                     #"{"name":"demo","steps":[{"label":"one","backend":"codex","prompt":"anything"}]}"#] {
            try recipe(body, in: root)
            XCTAssertThrowsError(try ExecutionPlan.resolve("demo", options: options(root)))
        }
    }

    private func cli(_ arguments: [String], workspace: URL) async throws -> AdapterResult {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try await ProcessRunner.run(
            executable: package.appendingPathComponent(".build/debug/mentu-recipes").path,
            arguments: arguments, env: ProcessInfo.processInfo.environment, workingDirectory: workspace,
            timeout: 10, maxOutputBytes: 100_000, eventSink: { _ in }
        )
    }

    func testConcurrentCLIProcessesDeduplicateAndExcludeDifferentIntents() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"echo once >> count; touch started; sleep 1"}]}"#, in: root)
        let digest = try ExecutionPlan.resolve("demo", options: options(root)).digest
        let arguments = ["run", "demo", "--workspace", root.path, "--plan-digest", digest, "--request-key", "first", "--quiet"]
        async let first = cli(arguments, workspace: root)
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path))
        let duplicate = try await cli(arguments, workspace: root)
        XCTAssertTrue(duplicate.stdout.contains("running"), duplicate.stdout + duplicate.stderr)
        let competing = try await cli(arguments.map { $0 == "first" ? "different" : $0 }, workspace: root)
        XCTAssertNotEqual(competing.exitCode, 0)
        XCTAssertTrue(competing.stderr.contains("in progress"), competing.stderr)
        let completed = try await first
        XCTAssertEqual(completed.exitCode, 0, completed.stderr)
        let repeated = try await cli(arguments, workspace: root)
        XCTAssertEqual(repeated.exitCode, 0, repeated.stderr)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("count")), "once\n")
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".mentu/runs").path)
        XCTAssertEqual(entries.filter { $0.hasPrefix("run_") }.count, 1)
    }

    func testCLIAdmissionTyposCannotStartLegacyWork() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt":"touch ran"}]}"#, in: root)
        for flags in [["--plan-digest"], ["--plan-dgiest", "bad"], ["--request-key", "one", "--request-key", "two"]] {
            let result = try await cli(["run", "demo", "--workspace", root.path] + flags, workspace: root)
            XCTAssertNotEqual(result.exitCode, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("ran").path))
    }

    func testRetryInvalidatesDependentEvidenceAndLeavesIndependentStepComplete() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","max_parallel":1,"steps":[{"label":"first","backend":"shell","prompt":"echo first >> count"},{"label":"dependent","backend":"shell","depends_on":["first"],"prompt":"echo dependent >> count"},{"label":"independent","backend":"shell","prompt":"echo independent >> count"}]}"#, in: root)
        let approved = try admitted(root)
        let first = try await RecipeRunner(options: approved).run("demo")
        let retried = try await RecipeRunner(options: options(root, digest: approved.planDigest, key: "retry-first"))
            .resume(runId: first.runId, retryStep: "first")
        XCTAssertEqual(retried.outcome, "ok")
        let lines = try String(contentsOf: root.appendingPathComponent("count")).split(separator: "\n")
        XCTAssertEqual(lines.filter { $0 == "first" }.count, 2)
        XCTAssertEqual(lines.filter { $0 == "dependent" }.count, 2)
        XCTAssertEqual(lines.filter { $0 == "independent" }.count, 1)
    }

    func testEqualLengthVariablesRenderInStableOrder() {
        XCTAssertEqual(PromptRenderer.render("$AA", vars: ["BB": "done", "AA": "$BB"]), "done")
        XCTAssertEqual(PromptRenderer.render("$AA", vars: ["AA": "$BB", "BB": "done"]), "done")
    }

    func testUnverifiableChildEvidenceKeepsWorkspaceClosed() async throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","type":"pipeline","steps":[],"recipes":[{"label":"child","recipe":"child"}]}"#, in: root)
        try recipe(#"{"name":"child","steps":[{"label":"one","backend":"shell","prompt":"exit 1"}]}"#, in: root, name: "child")
        let approved = try admitted(root)
        let first = try await RecipeRunner(options: approved).run("demo")
        let stateURL = root.appendingPathComponent(".mentu/runs/\(first.runId)/state.json")
        var state = try JSONDecoder().decode(RecipeRunState.self, from: Data(contentsOf: stateURL))
        state.childRunIds?["child"] = "run_missing"
        try JSONEncoder().encode(state).write(to: stateURL)
        let resumed = try await RecipeRunner(options: options(root, digest: approved.planDigest, key: "recover-missing"))
            .resume(runId: first.runId)
        XCTAssertEqual(resumed.steps.last?.executionUnverifiable, true)
        await expectFailure({
            _ = try await RecipeRunner(options: self.options(root, digest: approved.planDigest, key: "new-intent")).run("demo")
        }, contains: "unverifiable")
    }

    func testOversizedPromptIsRejectedBeforeExecution() throws {
        let root = try workspace()
        try recipe(#"{"name":"demo","steps":[{"label":"one","backend":"shell","prompt_file":"large.md"}]}"#, in: root)
        try put(String(repeating: "x", count: 4_194_305), ".mentu/prompts/large.md", in: root)
        XCTAssertThrowsError(try ExecutionPlan.resolve("demo", options: options(root)))
    }
}
