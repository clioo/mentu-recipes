import Darwin
import Foundation

public enum AdmissionError: Error, CustomStringConvertible {
    case invalidRequest
    case planChanged
    case requestConflict
    case busy(String?)
    case unverifiable(String)
    case legacyRecovery

    public var description: String {
        switch self {
        case .invalidRequest: return "Admission requires a SHA-256 plan digest and a 1-128 character request key"
        case .planChanged: return "Execution plan changed; review the current plan before starting or recovering"
        case .requestConflict: return "Request key was already used for a different plan or operation"
        case .busy(let run): return "Workspace has an admitted execution in progress: \(run ?? "reservation pending")"
        case .unverifiable(let run): return """
            Interrupted execution is unverifiable; refusing automatic takeover: \(run)
            Confirm nothing from that run is still running, then remove .mentu/runs/.admission/active.json to allow admitted work again.
            """
        case .legacyRecovery: return "This run has no admitted plan; recover it using the legacy workflow"
        }
    }
}

struct AdmissionReceipt: Codable {
    let version: Int
    let digest: String
    let operation: String
    let runId: String
    let requestHash: String
}

struct RunAdmission: Codable {
    let version: Int
    let digest: String
    let parentRunId: String?
}

final class WorkspaceAdmissionLease {
    let directory: URL
    private let descriptor: Int32

    init(workspace: URL) throws {
        let root = workspace.standardizedFileURL.resolvingSymlinksInPath()
        directory = root.appendingPathComponent(".mentu/runs/.admission")
        guard RecipePaths.isDescendant(directory, of: root) else { throw AdmissionError.invalidRequest }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("workspace.lock").path,
                      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw RecipeError.failed("Cannot open admission lease") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            let active = try? Self.read(AdmissionReceipt.self, at: directory.appendingPathComponent("active.json"))
            throw AdmissionError.busy(active?.runId)
        }
        descriptor = fd
    }

    deinit { flock(descriptor, LOCK_UN); close(descriptor) }

    static func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func write<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum AdmittedExecution {
    static func validate(_ options: RunOptions) throws -> (String, String) {
        guard let digest = options.planDigest, digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let key = options.requestKey, key.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", options: .regularExpression) != nil else {
            throw AdmissionError.invalidRequest
        }
        return (digest, ExecutionDigest.bytes(Data(key.utf8)))
    }

    static func execute(_ reference: String?, runId: String? = nil, retryStep: String? = nil,
                        options: RunOptions) async throws -> RecipeRunRecord {
        let (digest, requestHash) = try validate(options)
        let runs = RecipePaths(workspace: options.workspace, home: options.home).projectRuns
        var recipeReference = reference
        if let runId {
            try validateRunID(runId)
            let dir = runs.appendingPathComponent(runId)
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("admission.json").path) else {
                throw AdmissionError.legacyRecovery
            }
            let admission = try WorkspaceAdmissionLease.read(RunAdmission.self, at: dir.appendingPathComponent("admission.json"))
            guard admission.version == 1, admission.digest == digest else { throw AdmissionError.planChanged }
            guard admission.parentRunId == nil else { throw RecipeError.failed("Recover an admitted child through its parent run") }
            let snapshot = await (try RunStateStore.load(runDir: dir)).snapshot()
            if let retryStep, snapshot.steps[retryStep] == nil { throw RecipeError.failed("Unknown retry step: \(retryStep)") }
            guard snapshot.vars == options.vars, snapshot.backend == options.backend, snapshot.model == options.model else {
                throw AdmissionError.planChanged
            }
            recipeReference = snapshot.recipeRef
        }
        guard let recipeReference else { throw AdmissionError.invalidRequest }
        let captured = try ExecutionPlanResolver(options: options).capture(recipeReference)
        guard captured.review.digest == digest else { throw AdmissionError.planChanged }
        if let runId, let retryStep, captured.recipe.steps.isEmpty {
            let snapshot = await (try RunStateStore.load(runDir: runs.appendingPathComponent(runId))).snapshot()
            if snapshot.steps[retryStep]?.state.unblocksDependents == true {
                throw RecipeError.failed("Completed child recipes retain their identity; use a new run intent to execute them again")
            }
        }
        let operation = runId.map { "recover:\($0):\(retryStep ?? "")" } ?? "run"
        let lease: WorkspaceAdmissionLease
        do {
            lease = try WorkspaceAdmissionLease(workspace: options.workspace)
        } catch let error as AdmissionError {
            if case .busy = error,
               let existing = try lookupReceipt(requestHash, digest: digest, operation: operation, runs: runs) {
                return try RunReporter.load(runId: existing.runId, workspace: options.workspace)
            }
            throw error
        }
        // Keep the descriptor alive across all suspension points and child recipes.
        defer { withExtendedLifetime(lease) {} }
        if let existing = try lookupReceipt(requestHash, digest: digest, operation: operation, runs: runs) {
            let record = try RunReporter.load(runId: existing.runId, workspace: options.workspace)
            guard record.outcome != "running" else { throw AdmissionError.unverifiable(existing.runId) }
            return record
        }
        let activeURL = lease.directory.appendingPathComponent("active.json")
        if FileManager.default.fileExists(atPath: activeURL.path) {
            let active = try WorkspaceAdmissionLease.read(AdmissionReceipt.self, at: activeURL)
            // A lost parent process does not prove that its tools have stopped.
            throw AdmissionError.unverifiable(active.runId)
        }
        if let runId {
            let record = try RunReporter.load(runId: runId, workspace: options.workspace)
            guard record.outcome != "running" else { throw AdmissionError.unverifiable(runId) }
        }
        let target = runId ?? "run_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let receipt = AdmissionReceipt(version: 1, digest: digest, operation: operation, runId: target, requestHash: requestHash)
        try WorkspaceAdmissionLease.write(receipt, at: activeURL)
        try WorkspaceAdmissionLease.write(receipt, at: lease.directory.appendingPathComponent("\(requestHash).json"))
        let runner = RecipeRunner(options: options, captured: captured, parentRunId: nil)
        let record: RecipeRunRecord
        if runId != nil {
            record = try await runner.resume(runId: target, retryStep: retryStep)
        } else {
            record = try await runner.runCaptured(runId: target)
        }
        if record.outcome != "running", !record.steps.contains(where: { $0.exitCode == 124 || $0.executionUnverifiable == true }) {
            // A failed cleanup must not turn a finished run into an error.
            try? FileManager.default.removeItem(at: activeURL)
        }
        return record
    }

    static func validateRunID(_ runId: String) throws {
        guard runId.range(of: "^run_[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            throw RecipeError.failed("Invalid run identifier")
        }
    }

    private static func lookupReceipt(_ key: String, digest: String, operation: String, runs: URL) throws -> AdmissionReceipt? {
        let url = runs.appendingPathComponent(".admission/\(key).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let receipt = try WorkspaceAdmissionLease.read(AdmissionReceipt.self, at: url)
        guard receipt.version == 1, receipt.digest == digest, receipt.operation == operation, receipt.requestHash == key else {
            throw AdmissionError.requestConflict
        }
        try validateRunID(receipt.runId)
        return receipt
    }
}
