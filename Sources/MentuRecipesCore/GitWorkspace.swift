import Foundation
import Darwin

public struct StepGitRecord: Codable, Sendable {
    public let changedPaths: [String]
    public let committedHash: String?
    public let quarantineFiles: [String]
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case changedPaths = "changed_paths"
        case committedHash = "committed_hash"
        case quarantineFiles = "quarantine_files"
        case note
    }
}
enum GitWorkspace {
    static func finalizeStep(
        label: String,
        expectedChanges: [String]?,
        stepDir: URL,
        runDir: URL,
        runId: String
    ) async -> StepGitRecord? {
        guard let expectedChanges else { return nil }
        guard let git = ProcessRunner.findExecutable("git") else {
            return StepGitRecord(changedPaths: [], committedHash: nil, quarantineFiles: [], note: "git unavailable")
        }
        guard let repoRoot = await repositoryRoot(git: git, from: stepDir) else {
            return StepGitRecord(changedPaths: [], committedHash: nil, quarantineFiles: [], note: "not a git worktree")
        }

        let dirty = await dirtyPaths(git: git, repoRoot: repoRoot)
        let normalized = expectedChanges.compactMap { normalizeExpectedPath($0) }
        let matched = dirty.filter { path in normalized.contains { matches(pattern: $0, path: path) } }
        let unmatched = dirty.filter { !matched.contains($0) && !$0.hasPrefix(".mentu/runs/") }
        var quarantineFiles: [String] = []
        if !unmatched.isEmpty {
            if let file = try? quarantine(paths: unmatched, git: git, repoRoot: repoRoot, runDir: runDir, runId: runId, label: label) {
                quarantineFiles.append(file.path)
            }
        }

        guard !matched.isEmpty else {
            return StepGitRecord(
                changedPaths: dirty,
                committedHash: nil,
                quarantineFiles: quarantineFiles,
                note: dirty.isEmpty ? "no changes" : "no changes matched expected_changes"
            )
        }

        _ = try? await ProcessRunner.run(
            executable: git,
            arguments: ["add"] + matched,
            env: ProcessInfo.processInfo.environment,
            workingDirectory: repoRoot,
            timeout: 30,
            maxOutputBytes: 1_000_000,
            eventSink: { _ in }
        )
        let commit = try? await ProcessRunner.run(
            executable: git,
            arguments: ["commit", "-m", "chore: mentu-recipes step \(label) (\(runId))"],
            env: commitEnvironment(),
            workingDirectory: repoRoot,
            timeout: 60,
            maxOutputBytes: 1_000_000,
            eventSink: { _ in }
        )
        let hash = await headHash(git: git, repoRoot: repoRoot)
        return StepGitRecord(
            changedPaths: dirty,
            committedHash: commit?.exitCode == 0 ? hash : nil,
            quarantineFiles: quarantineFiles,
            note: commit?.exitCode == 0 ? nil : "git commit did not create a commit"
        )
    }

    private static func repositoryRoot(git: String, from dir: URL) async -> URL? {
        guard let result = try? await ProcessRunner.run(
            executable: git,
            arguments: ["rev-parse", "--show-toplevel"],
            env: ProcessInfo.processInfo.environment,
            workingDirectory: dir,
            timeout: 10,
            maxOutputBytes: 20_000,
            eventSink: { _ in }
        ), result.exitCode == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    private static func dirtyPaths(git: String, repoRoot: URL) async -> [String] {
        guard let result = try? await ProcessRunner.run(
            executable: git,
            arguments: ["status", "--porcelain=v1"],
            env: ProcessInfo.processInfo.environment,
            workingDirectory: repoRoot,
            timeout: 10,
            maxOutputBytes: 1_000_000,
            eventSink: { _ in }
        ), result.exitCode == 0 else { return [] }
        return result.stdout.split(separator: "\n").map { porcelainPath(String($0)) }.filter { !$0.isEmpty }.sorted()
    }

    static func porcelainPath(_ row: String) -> String {
        guard row.count >= 4 else { return row.trimmingCharacters(in: .whitespaces) }
        let pathStart = row.index(row.startIndex, offsetBy: 3)
        let raw = String(row[pathStart...]).trimmingCharacters(in: .whitespaces)
        if let range = raw.range(of: " -> ") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    private static func normalizeExpectedPath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private static func matches(pattern: String, path: String) -> Bool {
        if fnmatch(pattern, path, 0) == 0 { return true }
        if !pattern.contains("*") && !pattern.contains("?") {
            return path == pattern || path.hasPrefix(pattern + "/")
        }
        return false
    }

    private static func quarantine(paths: [String], git: String, repoRoot: URL, runDir: URL, runId: String, label: String) throws -> URL {
        let dir = runDir.appendingPathComponent("quarantine", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(runId)-\(label)-quarantine.patch")
        var body = "# Quarantined changes outside expected_changes\n"
        body += "# Step: \(label)\n\n"
        if let diff = try? awaitProcess(git: git, repoRoot: repoRoot, args: ["diff", "HEAD", "--"] + paths), !diff.isEmpty {
            body += diff
            body += "\n"
        }
        for path in paths {
            let url = repoRoot.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path),
               let text = try? String(contentsOf: url, encoding: .utf8),
               !body.contains("+++ b/\(path)") {
                body += "\n# Untracked or binary-safe text capture: \(path)\n"
                body += text
                body += "\n"
            }
        }
        try body.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func awaitProcess(git: String, repoRoot: URL, args: [String]) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var output = ""
        Task {
            let result = try? await ProcessRunner.run(
                executable: git,
                arguments: args,
                env: ProcessInfo.processInfo.environment,
                workingDirectory: repoRoot,
                timeout: 20,
                maxOutputBytes: 2_000_000,
                eventSink: { _ in }
            )
            output = result?.stdout ?? ""
            semaphore.signal()
        }
        semaphore.wait()
        return output
    }

    private static func headHash(git: String, repoRoot: URL) async -> String? {
        guard let result = try? await ProcessRunner.run(
            executable: git,
            arguments: ["rev-parse", "HEAD"],
            env: ProcessInfo.processInfo.environment,
            workingDirectory: repoRoot,
            timeout: 10,
            maxOutputBytes: 20_000,
            eventSink: { _ in }
        ), result.exitCode == 0 else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func commitEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_AUTHOR_NAME"] = env["GIT_AUTHOR_NAME"] ?? "Mentu Recipes"
        env["GIT_AUTHOR_EMAIL"] = env["GIT_AUTHOR_EMAIL"] ?? "recipes@mentu.ai"
        env["GIT_COMMITTER_NAME"] = env["GIT_COMMITTER_NAME"] ?? env["GIT_AUTHOR_NAME"]
        env["GIT_COMMITTER_EMAIL"] = env["GIT_COMMITTER_EMAIL"] ?? env["GIT_AUTHOR_EMAIL"]
        return env
    }
}
