import Foundation
import Darwin

public enum Verification {
    public static func verify(_ requirements: VerifyRequirements?, stepDir: URL) async throws {
        guard let requirements else { return }

        for check in requirements.grepPresent ?? [] {
            let content = try read(check.file, from: stepDir)
            let count = content.components(separatedBy: check.pattern).count - 1
            let min = check.min ?? 1
            if count < min {
                throw RecipeError.failed(check.description ?? "\(check.file) must contain '\(check.pattern)' at least \(min) time(s)")
            }
            if let max = check.max, count > max {
                throw RecipeError.failed(check.description ?? "\(check.file) must contain '\(check.pattern)' at most \(max) time(s)")
            }
        }

        for check in requirements.grepAbsent ?? [] {
            let content = try read(check.file, from: stepDir)
            if content.contains(check.pattern) {
                throw RecipeError.failed(check.description ?? "\(check.file) must not contain '\(check.pattern)'")
            }
        }

        for check in requirements.fileAbsent ?? [] {
            let path = try scopedURL(check.file, from: stepDir).path
            if FileManager.default.fileExists(atPath: path) {
                throw RecipeError.failed(check.description ?? "\(check.file) must not exist")
            }
        }

        if let allowed = requirements.gitCleanOutside {
            try await verifyGitCleanOutside(allowed, stepDir: stepDir)
        }

        for command in requirements.commands ?? [] {
            let result = try await ProcessRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", command],
                env: ProcessInfo.processInfo.environment,
                workingDirectory: stepDir,
                timeout: 300,
                maxOutputBytes: 1_000_000,
                eventSink: { _ in }
            )
            if result.exitCode != 0 {
                throw RecipeError.failed("Verification command failed: \(command)\n\(result.stderr)")
            }
        }
    }

    private static func read(_ relative: String, from stepDir: URL) throws -> String {
        let url = try scopedURL(relative, from: stepDir)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecipeError.failed("Verification file missing: \(relative)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func scopedURL(_ relative: String, from stepDir: URL) throws -> URL {
        guard !relative.hasPrefix("/"), !relative.hasPrefix("~") else {
            throw RecipeError.failed("Verification path must be relative to the step directory: \(relative)")
        }
        let url = stepDir.appendingPathComponent(relative).standardizedFileURL
        guard RecipePaths.isDescendant(url, of: stepDir) else {
            throw RecipeError.failed("Verification path escapes the step directory: \(relative)")
        }
        return url
    }

    private static func verifyGitCleanOutside(_ allowed: [String], stepDir: URL) async throws {
        guard ProcessRunner.findExecutable("git") != nil else { return }
        let result = try await ProcessRunner.run(
            executable: ProcessRunner.findExecutable("git")!,
            arguments: ["status", "--porcelain"],
            env: ProcessInfo.processInfo.environment,
            workingDirectory: stepDir,
            timeout: 10,
            maxOutputBytes: 1_000_000,
            eventSink: { _ in }
        )
        guard result.exitCode == 0 else { return }
        let dirty = result.stdout.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let last = parts.last else { return nil }
            return String(last)
        }
        let offenders = dirty.filter { path in
            !allowed.contains { pattern in fnmatch(pattern, path, 0) == 0 || path.hasPrefix(pattern) }
        }
        if !offenders.isEmpty {
            throw RecipeError.failed("Dirty files outside allowed paths: \(offenders.joined(separator: ", "))")
        }
    }
}
