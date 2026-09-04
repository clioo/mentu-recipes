import Foundation
import Darwin

public struct VerificationIssue: Codable, Sendable {
    public let kind: String
    public let file: String?
    public let message: String

    public init(kind: String, file: String? = nil, message: String) {
        self.kind = kind
        self.file = file
        self.message = message
    }
}

public struct VerificationOutcome: Codable, Sendable {
    public let warnings: [VerificationIssue]
    public let errors: [VerificationIssue]

    public var passed: Bool { errors.isEmpty }
    public var hasWarnings: Bool { !warnings.isEmpty }
}

public enum Verification {
    public static func verify(_ requirements: VerifyRequirements?, stepDir: URL) async throws {
        let outcome = try await evaluate(requirements, stepDir: stepDir, preStepBaseline: nil)
        if let first = outcome.errors.first {
            throw RecipeError.failed(first.message)
        }
    }

    public static func evaluate(
        _ requirements: VerifyRequirements?,
        stepDir: URL,
        preStepBaseline: WorkspaceBaseline?,
        environment: [String: String]? = nil
    ) async throws -> VerificationOutcome {
        var warnings: [VerificationIssue] = []
        var errors: [VerificationIssue] = []
        guard let requirements else {
            return VerificationOutcome(warnings: [], errors: [])
        }

        for check in requirements.grepPresent ?? [] {
            guard let content = try? read(check.file, from: stepDir) else {
                warnings.append(.init(
                    kind: "grep_present",
                    file: check.file,
                    message: check.description ?? "Bookkeeping warning: verification file missing for grep_present: \(check.file)"
                ))
                continue
            }
            let count = content.components(separatedBy: check.pattern).count - 1
            let min = check.min ?? 1
            if count < min {
                warnings.append(.init(
                    kind: "grep_present",
                    file: check.file,
                    message: check.description ?? "Bookkeeping warning: \(check.file) contains '\(check.pattern)' \(count) time(s), expected at least \(min)"
                ))
            }
            if let max = check.max, count > max {
                warnings.append(.init(
                    kind: "grep_present",
                    file: check.file,
                    message: check.description ?? "Bookkeeping warning: \(check.file) contains '\(check.pattern)' \(count) time(s), expected at most \(max)"
                ))
            }
        }

        for check in requirements.grepAbsent ?? [] {
            guard let content = try? read(check.file, from: stepDir) else {
                warnings.append(.init(
                    kind: "grep_absent",
                    file: check.file,
                    message: check.description ?? "Bookkeeping warning: verification file missing for grep_absent: \(check.file)"
                ))
                continue
            }
            if content.contains(check.pattern) {
                warnings.append(.init(
                    kind: "grep_absent",
                    file: check.file,
                    message: check.description ?? "Bookkeeping warning: \(check.file) still contains '\(check.pattern)'"
                ))
            }
        }

        for check in requirements.fileAbsent ?? [] {
            let path = try scopedURL(check.file, from: stepDir).path
            if FileManager.default.fileExists(atPath: path) {
                errors.append(.init(
                    kind: "file_absent",
                    file: check.file,
                    message: check.description ?? "\(check.file) must not exist"
                ))
            }
        }

        if let allowed = requirements.gitCleanOutside {
            errors += await gitCleanOutsideIssues(allowed, stepDir: stepDir, preStepBaseline: preStepBaseline)
        }

        for command in requirements.commands ?? [] {
            let result = try await ProcessRunner.run(
                executable: "/bin/sh",
                arguments: ["-c", command],
                env: environment ?? ProcessInfo.processInfo.environment,
                workingDirectory: stepDir,
                timeout: 300,
                maxOutputBytes: 1_000_000,
                eventSink: { _ in }
            )
            if result.exitCode != 0 {
                errors.append(.init(
                    kind: "command",
                    message: "Verification command failed: \(command)\n\(result.stderr)"
                ))
            }
        }

        return VerificationOutcome(warnings: warnings, errors: errors)
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

    private static func gitCleanOutsideIssues(
        _ allowed: [String],
        stepDir: URL,
        preStepBaseline: WorkspaceBaseline?
    ) async -> [VerificationIssue] {
        guard ProcessRunner.findExecutable("git") != nil else { return [] }
        let before = preStepBaseline ?? WorkspaceBaseline(capturedAt: "", gitRoot: nil, head: nil, dirtyPaths: [], untrackedPaths: [])
        let after = await WorkspaceBaselineManager.capture(from: stepDir)
        let drift = WorkspaceBaselineManager.classify(before: before, after: after, expectedChanges: allowed)
        let offenders = drift.unexpectedPaths
        guard !offenders.isEmpty else { return [] }
        return [
            .init(
                kind: "git_clean_outside",
                message: "Dirty files outside allowed paths: \(offenders.joined(separator: ", "))"
            )
        ]
    }
}
