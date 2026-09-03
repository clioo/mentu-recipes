import XCTest
@testable import MentuRecipesCore

final class OnboardingTests: XCTestCase {
    func testExampleRecipeDecodes() throws {
        let data = Data(Onboarding.exampleRecipeJSON.utf8)
        let recipe = try JSONDecoder().decode(RecipeDefinition.self, from: data)
        XCTAssertEqual(recipe.name, Onboarding.exampleName)
        XCTAssertEqual(recipe.steps.count, 2)
        XCTAssertEqual(recipe.steps.compactMap { $0.backend }, ["shell", "shell"])
    }

    func testScaffoldWritesOnceAndNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try Onboarding.scaffoldExample(into: dir)
        XCTAssertTrue(first.written)
        try "custom".write(to: first.url, atomically: true, encoding: .utf8)
        let second = try Onboarding.scaffoldExample(into: dir)
        XCTAssertFalse(second.written)
        XCTAssertEqual(try String(contentsOf: second.url, encoding: .utf8), "custom")
    }

    func testIgnoreRunArtifactsWritesOnceAndKeepsRecipesTracked() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-ignore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(try Onboarding.ignoreRunArtifacts(in: dir))
        let url = dir.appendingPathComponent(".mentu/.gitignore")
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.contains("runs/"))
        XCTAssertTrue(body.contains("cache/"))
        XCTAssertFalse(body.contains("recipes"))
        XCTAssertFalse(body.contains("prompts"))

        try "custom\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(try Onboarding.ignoreRunArtifacts(in: dir))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "custom\n")
    }

    func testExampleRunsWithShellBackend() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Onboarding.scaffoldExample(into: dir)
        let runner = RecipeRunner(options: RunOptions(workspace: dir, quiet: true))
        let record = try await runner.run(Onboarding.exampleName)
        XCTAssertEqual(record.outcome, "ok")
        XCTAssertEqual(record.steps.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("examples/.work/hello.md").path))
    }
}
