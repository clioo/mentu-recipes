import Foundation

public struct RunEvent: Codable, Sendable {
    public let id: String
    public let runId: String
    public let sequence: Int
    public let timestamp: String
    public let kind: RunEventKind
    public let recipeName: String
    public let stepLabel: String?
    public let backend: String?
    public let status: String?
    public let message: String?
    public let data: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case runId = "run_id"
        case sequence, timestamp, kind
        case recipeName = "recipe_name"
        case stepLabel = "step_label"
        case backend, status, message, data
    }
}

public enum RunEventKind: String, Codable, Sendable {
    case runStarted = "run_started"
    case runFinished = "run_finished"
    case runResumed = "run_resumed"
    case stepQueued = "step_queued"
    case stepSkipped = "step_skipped"
    case stepStarted = "step_started"
    case stepRetried = "step_retried"
    case stepFinished = "step_finished"
    case backendSelected = "backend_selected"
    case verificationStarted = "verification_started"
    case verificationFinished = "verification_finished"
    case hookStarted = "hook_started"
    case hookFinished = "hook_finished"
    case workspaceDrift = "workspace_drift"
    case quarantineWritten = "quarantine_written"
    case error = "error"
}

public actor RunEventWriter {
    public let url: URL
    private let runId: String
    private let recipeName: String
    private var sequence: Int

    public init(runId: String, recipeName: String, runDir: URL, startingSequence: Int = 0) {
        self.runId = runId
        self.recipeName = recipeName
        self.url = runDir.appendingPathComponent("events.jsonl")
        self.sequence = startingSequence
    }

    public func emit(
        _ kind: RunEventKind,
        stepLabel: String? = nil,
        backend: String? = nil,
        status: String? = nil,
        message: String? = nil,
        data: [String: String]? = nil
    ) async {
        sequence += 1
        let event = RunEvent(
            id: "evt_\(String(format: "%06d", sequence))",
            runId: runId,
            sequence: sequence,
            timestamp: Self.isoNow(),
            kind: kind,
            recipeName: recipeName,
            stepLabel: stepLabel,
            backend: backend,
            status: status,
            message: message,
            data: data
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let line = try JSONEncoder.sorted.encode(event) + Data("\n".utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: url)
            }
        } catch {
            // Event logging must never take down local execution.
        }
    }

    public static func load(from url: URL) -> [RunEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RunEvent.self, from: data)
        }
    }

    public static func lastSequence(in url: URL) -> Int {
        load(from: url).map(\.sequence).max() ?? 0
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
