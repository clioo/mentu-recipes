import XCTest
@testable import MentuRecipesCore

final class AdmissionFollowUpTests: XCTestCase {
    private func workspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("admission-followup-\(UUID().uuidString)")
        try Onboarding.scaffoldExample(into: dir)
        return dir
    }

    func testDigestIgnoresSessionScopedEnvironmentButBindsTheRest() throws {
        let dir = try workspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let options = RunOptions(workspace: dir)
        let base: [String: String] = ["PATH": "/usr/bin:/bin", "HOME": dir.path]

        let first = try ExecutionPlanResolver(options: options, environment: base).capture(Onboarding.exampleName).review
        var otherTab = base
        otherTab["TERM_SESSION_ID"] = "w1t3p0:ABCD"
        otherTab["ITERM_SESSION_ID"] = "w1t3p0"
        otherTab["SSH_AUTH_SOCK"] = "/tmp/other.sock"
        otherTab["TMPDIR"] = "/var/folders/zz/T/"
        let second = try ExecutionPlanResolver(options: options, environment: otherTab).capture(Onboarding.exampleName).review
        XCTAssertEqual(first.digest, second.digest, "session-scoped variables must not change the plan")
        XCTAssertTrue(first.unboundEnvironment.contains("TERM_SESSION_ID"))

        var realChange = base
        realChange["PATH"] = "/opt/elsewhere/bin:/usr/bin:/bin"
        let third = try ExecutionPlanResolver(options: options, environment: realChange).capture(Onboarding.exampleName).review
        XCTAssertNotEqual(first.digest, third.digest, "an environment a step reads must still be bound")
    }

    func testUnverifiableErrorNamesTheMarkerFile() {
        let text = AdmissionError.unverifiable("run_X").description
        XCTAssertTrue(text.contains(".mentu/runs/.admission/active.json"))
    }

    func testTimeoutStopsTheStepInsteadOfWaitingForIt() async throws {
        let dir = FileManager.default.temporaryDirectory
        let started = Date()
        let result = try await ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "sleep 10; echo LATE"],
            env: ["PATH": "/usr/bin:/bin"], workingDirectory: dir,
            timeout: 1, maxOutputBytes: 10_000, eventSink: { _ in }
        )
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result.exitCode, 124)
        XCTAssertLessThan(elapsed, 5, "a 1 second timeout must not wait for a 10 second process")
        XCTAssertFalse(result.stdout.contains("LATE"))
    }
}
