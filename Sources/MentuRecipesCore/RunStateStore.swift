import Foundation

public enum StepExecutionState: String, Codable, Sendable {
    case pending
    case running
    case success
    case warnBookkeeping = "warn_bookkeeping"
    case failed
    case skipped
    case cancelled

    public var unblocksDependents: Bool {
        self == .success || self == .warnBookkeeping
    }
}

public struct StepStateRecord: Codable, Sendable {
    public var label: String
    public var state: StepExecutionState
    public var attempts: Int
    public var updatedAt: String
    public var lastOutcome: String?
    public var lastMessage: String?

    enum CodingKeys: String, CodingKey {
        case label, state, attempts
        case updatedAt = "updated_at"
        case lastOutcome = "last_outcome"
        case lastMessage = "last_message"
    }
}

public struct RecipeRunState: Codable, Sendable {
    public var runId: String
    public var recipeName: String
    public var recipeRef: String
    public var startedAt: String
    public var updatedAt: String
    public var backend: String?
    public var model: String?
    public var vars: [String: String]
    public var steps: [String: StepStateRecord]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case recipeName = "recipe_name"
        case recipeRef = "recipe_ref"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case backend, model, vars, steps
    }
}

public actor RunStateStore {
    public let url: URL
    private var state: RecipeRunState

    public init(state: RecipeRunState, url: URL) {
        self.state = state
        self.url = url
    }

    public static func create(
        runId: String,
        recipeName: String,
        recipeRef: String,
        backend: String?,
        model: String?,
        vars: [String: String],
        labels: [String],
        runDir: URL
    ) async throws -> RunStateStore {
        let now = isoNow()
        let steps = Dictionary(uniqueKeysWithValues: labels.map {
            ($0, StepStateRecord(label: $0, state: .pending, attempts: 0, updatedAt: now, lastOutcome: nil, lastMessage: nil))
        })
        let state = RecipeRunState(
            runId: runId,
            recipeName: recipeName,
            recipeRef: recipeRef,
            startedAt: now,
            updatedAt: now,
            backend: backend,
            model: model,
            vars: vars,
            steps: steps
        )
        let store = RunStateStore(state: state, url: runDir.appendingPathComponent("state.json"))
        try await store.save()
        return store
    }

    public static func load(runDir: URL) throws -> RunStateStore {
        let url = runDir.appendingPathComponent("state.json")
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder().decode(RecipeRunState.self, from: data)
        return RunStateStore(state: state, url: url)
    }

    public func snapshot() -> RecipeRunState {
        state
    }

    public func record(
        label: String,
        state next: StepExecutionState,
        message: String? = nil,
        incrementAttempts: Bool = false
    ) async throws {
        let now = Self.isoNow()
        var record = state.steps[label] ?? StepStateRecord(label: label, state: .pending, attempts: 0, updatedAt: now, lastOutcome: nil, lastMessage: nil)
        record.state = next
        if incrementAttempts { record.attempts += 1 }
        record.updatedAt = now
        record.lastOutcome = next.rawValue
        record.lastMessage = message
        state.steps[label] = record
        state.updatedAt = now
        try save()
    }

    public func shouldSkipCompleted(label: String, retryStep: String?) -> Bool {
        guard retryStep != label else { return false }
        guard let step = state.steps[label] else { return false }
        return step.state.unblocksDependents
    }

    public func isDependencyComplete(_ label: String) -> Bool {
        state.steps[label]?.state.unblocksDependents == true
    }

    public func markRetryTarget(_ label: String) async throws {
        try await record(label: label, state: .pending, message: "retry requested")
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: url)
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
