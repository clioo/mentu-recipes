import Foundation
import Darwin

public struct WorkspaceBaseline: Codable, Sendable {
    public let capturedAt: String
    public let gitRoot: String?
    public let head: String?
    public let dirtyPaths: [String]
    public let untrackedPaths: [String]

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case gitRoot = "git_root"
        case head
        case dirtyPaths = "dirty_paths"
        case untrackedPaths = "untracked_paths"
    }
}

public struct WorkspaceDrift: Codable, Sendable {
    public let preexistingPaths: [String]
    public let createdPaths: [String]
    public let expectedPaths: [String]
    public let unexpectedPaths: [String]
    public let ignoredRunStatePaths: [String]

    enum CodingKeys: String, CodingKey {
        case preexistingPaths = "preexisting_paths"
        case createdPaths = "created_paths"
        case expectedPaths = "expected_paths"
        case unexpectedPaths = "unexpected_paths"
        case ignoredRunStatePaths = "ignored_run_state_paths"
    }
}

public enum WorkspaceBaselineManager {
    public static func capture(from stepDir: URL) async -> WorkspaceBaseline {
        guard let git = ProcessRunner.findExecutable("git"),
              let root = await repositoryRoot(git: git, from: stepDir) else {
            return WorkspaceBaseline(capturedAt: isoNow(), gitRoot: nil, head: nil, dirtyPaths: [], untrackedPaths: [])
        }
        let head = await headHash(git: git, repoRoot: root)
        let entries = await porcelainEntries(git: git, repoRoot: root)
        let dirty = entries.map(\.path).sorted()
        let untracked = entries.filter { $0.status == "??" }.map(\.path).sorted()
        return WorkspaceBaseline(capturedAt: isoNow(), gitRoot: root.path, head: head, dirtyPaths: dirty, untrackedPaths: untracked)
    }

    public static func classify(
        before: WorkspaceBaseline,
        after: WorkspaceBaseline,
        expectedChanges: [String]?
    ) -> WorkspaceDrift {
        let beforeSet = Set(before.dirtyPaths)
        let afterSet = Set(after.dirtyPaths)
        let preexisting = afterSet.intersection(beforeSet)
        let newPaths = afterSet.subtracting(beforeSet)
        let ignored = newPaths.filter { isRunnerOwned($0) }
        let created = newPaths.subtracting(ignored)
        let expected = created.filter { path in matchesAny(path: path, patterns: expectedChanges ?? []) }
        let unexpected = created.subtracting(expected)
        return WorkspaceDrift(
            preexistingPaths: preexisting.sorted(),
            createdPaths: created.sorted(),
            expectedPaths: expected.sorted(),
            unexpectedPaths: unexpected.sorted(),
            ignoredRunStatePaths: ignored.sorted()
        )
    }

    public static func matchesAny(path: String, patterns: [String]) -> Bool {
        patterns.compactMap(normalizePattern).contains { pattern in
            if fnmatch(pattern, path, 0) == 0 { return true }
            if !pattern.contains("*") && !pattern.contains("?") {
                return path == pattern || path.hasPrefix(pattern + "/")
            }
            return false
        }
    }

    public static func isRunnerOwned(_ path: String) -> Bool {
        path.hasPrefix(".mentu/runs/") || path.hasPrefix(".mentu/cache/")
    }

    public static func repositoryRoot(git: String, from dir: URL) async -> URL? {
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

    public static func porcelainPath(_ row: String) -> String {
        guard row.count >= 4 else { return row.trimmingCharacters(in: .whitespaces) }
        let pathStart = row.index(row.startIndex, offsetBy: 3)
        let raw = String(row[pathStart...]).trimmingCharacters(in: .whitespaces)
        if let range = raw.range(of: " -> ") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    private static func porcelainEntries(git: String, repoRoot: URL) async -> [(status: String, path: String)] {
        guard let result = try? await ProcessRunner.run(
            executable: git,
            arguments: ["status", "--porcelain=v1", "-uall"],
            env: ProcessInfo.processInfo.environment,
            workingDirectory: repoRoot,
            timeout: 10,
            maxOutputBytes: 1_000_000,
            eventSink: { _ in }
        ), result.exitCode == 0 else { return [] }
        return result.stdout.split(separator: "\n").map { row in
            let text = String(row)
            let status = text.count >= 2 ? String(text.prefix(2)) : ""
            return (status, porcelainPath(text))
        }.filter { !$0.path.isEmpty }
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

    private static func normalizePattern(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
