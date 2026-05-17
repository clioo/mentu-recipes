import Foundation

public struct StepRunRecord: Codable, Sendable {
    public let label: String
    public let backend: String
    public let model: String?
    public let exitCode: Int32
    public let localComplete: Bool
    public let cloudComplete: Bool?
    public let trustScore: Double?
    public let durationSeconds: Int
    public let attempts: Int
    public let outputFile: String
    public let errorFile: String
}

public struct RecipeRunRecord: Codable, Sendable {
    public let runId: String
    public let recipeName: String
    public let startedAt: String
    public var endedAt: String?
    public var outcome: String
    public var cloudRunId: String?
    public var cloudMode: String
    public var steps: [StepRunRecord]
}

public final class RecipeRunner {
    private let options: RunOptions
    private let paths: RecipePaths
    private let store: RecipeStore
    private let renderer: PromptRenderer

    public init(options: RunOptions) {
        self.options = options
        self.paths = RecipePaths(workspace: options.workspace, home: options.home)
        self.store = RecipeStore(paths: paths)
        self.renderer = PromptRenderer(paths: paths)
    }

    public func run(_ nameOrPath: String) async throws -> RecipeRunRecord {
        let (recipe, _) = try store.load(nameOrPath)
        let ordered = try store.topologicalOrder(recipe.steps)
        let runId = "run_\(Self.timestampForID())_\(UUID().uuidString.prefix(8))"
        let runDir = paths.projectRuns.appendingPathComponent(runId)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let baseEnv = mergedEnvironment(recipeEnv: recipe.env, stepEnv: nil, vars: options.vars)
        let cloud = options.cloudEnabled && (recipe.cloud?.enabled ?? true)
            ? MentuCloudClient.configured(baseURL: options.cloudBaseURL, env: baseEnv)
            : nil

        var record = RecipeRunRecord(
            runId: runId,
            recipeName: recipe.name,
            startedAt: Self.isoNow(),
            endedAt: nil,
            outcome: "running",
            cloudRunId: nil,
            cloudMode: cloud == nil ? "local-only" : "enabled",
            steps: []
        )
        try write(record, to: runDir.appendingPathComponent("run.json"))

        if let cloud {
            do {
                let start = try await cloud.startRun(recipeName: recipe.name, workspaceID: options.workspace.lastPathComponent)
                record.cloudRunId = start.runId
                try write(record, to: runDir.appendingPathComponent("run.json"))
            } catch {
                record.cloudMode = "unavailable"
            }
        }

        var overallOK = true
        for step in ordered {
            do {
                let stepRecord = try await runStep(step, recipe: recipe, runDir: runDir, cloud: cloud, cloudRunId: record.cloudRunId)
                record.steps.append(stepRecord)
                if !(stepRecord.cloudComplete ?? stepRecord.localComplete) {
                    overallOK = false
                    break
                }
            } catch {
                overallOK = false
                let failed = StepRunRecord(
                    label: step.label,
                    backend: step.backend ?? options.backend ?? recipe.backend ?? "unresolved",
                    model: step.model ?? options.model ?? recipe.model,
                    exitCode: 1,
                    localComplete: false,
                    cloudComplete: nil,
                    trustScore: nil,
                    durationSeconds: 0,
                    attempts: 0,
                    outputFile: "\(step.label).stdout",
                    errorFile: "\(step.label).stderr"
                )
                record.steps.append(failed)
                try? String(describing: error).write(to: runDir.appendingPathComponent(failed.errorFile), atomically: true, encoding: .utf8)
                break
            }
            try write(record, to: runDir.appendingPathComponent("run.json"))
        }

        record.outcome = overallOK ? "ok" : "failed"
        record.endedAt = Self.isoNow()
        if let cloudRunId = record.cloudRunId, let cloud {
            _ = try? await cloud.endRun(runId: cloudRunId, outcome: record.outcome)
        }
        try write(record, to: runDir.appendingPathComponent("run.json"))
        return record
    }

    private func runStep(
        _ step: RecipeStep,
        recipe: RecipeDefinition,
        runDir: URL,
        cloud: MentuCloudClient?,
        cloudRunId: String?
    ) async throws -> StepRunRecord {
        let backendName = step.backend ?? options.backend ?? recipe.backend
        let env = mergedEnvironment(recipeEnv: recipe.env, stepEnv: step.env, vars: options.vars)
        let adapter: BackendAdapter
        if let backendName {
            guard let resolved = AdapterRegistry.adapter(named: backendName, providers: recipe.providers ?? [:]) else {
                throw RecipeError.backendUnavailable(backendName)
            }
            adapter = resolved
        } else if let detected = AdapterRegistry.autoDetect(env: env) {
            adapter = detected
        } else {
            throw RecipeError.missingBackend(label: step.label)
        }

        guard adapter.isAvailable(env: env) else {
            throw RecipeError.backendUnavailable(adapter.name)
        }

        let promptVars = env.merging(options.vars) { _, new in new }
        let prompt = try renderer.prompt(for: step, vars: promptVars)
        let stepDir = try resolveStepDirectory(step.dir)
        let timeout = step.timeout ?? 1800
        let maxOutputBytes = step.maxOutputBytes ?? 5_000_000
        let attemptsAllowed = max(0, step.maxRetries ?? 0) + 1
        let model = step.model ?? options.model ?? recipe.model

        var lastResult: AdapterResult?
        var lastLocalComplete = false
        let start = Date()
        var attempts = 0

        for attempt in 1...attemptsAllowed {
            attempts = attempt
            if !options.quiet {
                print("▶ \(step.label) · \(adapter.name)")
            }
            let result = try await adapter.execute(
                AdapterRequest(
                    prompt: prompt,
                    systemContext: nil,
                    model: model,
                    env: env,
                    timeout: timeout,
                    maxOutputBytes: maxOutputBytes,
                    reasoning: step.reasoning,
                    maxOutputTokens: step.maxOutputTokens,
                    workingDirectory: stepDir
                ),
                eventSink: { text in
                    if !self.options.quiet {
                        FileHandle.standardOutput.write(Data(text.utf8))
                    }
                }
            )
            lastResult = result
            lastLocalComplete = localComplete(step: step, adapter: adapter, result: result)
            if lastLocalComplete {
                try await Verification.verify(step.verify, stepDir: stepDir)
                break
            }
            if attempt < attemptsAllowed {
                let backoff = step.retryBackoffMs ?? 1000
                try await Task.sleep(nanoseconds: UInt64(backoff) * 1_000_000)
            }
        }

        guard let result = lastResult else {
            throw RecipeError.failed("Step did not run: \(step.label)")
        }

        let stdoutFile = "\(step.label).stdout"
        let stderrFile = "\(step.label).stderr"
        try result.stdout.write(to: runDir.appendingPathComponent(stdoutFile), atomically: true, encoding: .utf8)
        try result.stderr.write(to: runDir.appendingPathComponent(stderrFile), atomically: true, encoding: .utf8)

        var cloudComplete: Bool?
        var trustScore: Double?
        if let cloud, recipe.cloud?.evaluateSteps == true {
            let tail = String(result.stdout.suffix(8000))
            do {
                let verdict = try await cloud.evaluateStep(.init(
                    run_id: cloudRunId,
                    recipe_name: recipe.name,
                    step_label: step.label,
                    backend: adapter.name,
                    model: model,
                    exit_code: result.exitCode,
                    local_complete: lastLocalComplete,
                    output_tail: tail,
                    duration_seconds: Int(Date().timeIntervalSince(start))
                ))
                cloudComplete = verdict.complete
                trustScore = verdict.trust_score
            } catch {
                cloudComplete = nil
            }
        }

        return StepRunRecord(
            label: step.label,
            backend: adapter.name,
            model: model,
            exitCode: result.exitCode,
            localComplete: lastLocalComplete,
            cloudComplete: cloudComplete,
            trustScore: trustScore,
            durationSeconds: Int(Date().timeIntervalSince(start)),
            attempts: attempts,
            outputFile: stdoutFile,
            errorFile: stderrFile
        )
    }

    private func localComplete(step: RecipeStep, adapter: BackendAdapter, result: AdapterResult) -> Bool {
        guard result.exitCode == 0 else { return false }
        if let keyword = step.completionKeyword, !keyword.isEmpty {
            return result.stdout.contains(keyword) || result.stderr.contains(keyword)
        }
        switch adapter.completionPolicy {
        case .shellExitCode:
            return result.exitCode == 0
        case .providerCompleteEvent:
            return result.providerCompleted
        case .keywordRequired:
            return false
        }
    }

    private func resolveStepDirectory(_ dir: String?) throws -> URL {
        guard let dir, !dir.isEmpty else { return options.workspace }
        guard !dir.hasPrefix("/"), !dir.hasPrefix("~") else {
            throw RecipeError.failed("Step dir must stay inside the workspace: \(dir)")
        }
        let url = options.workspace.appendingPathComponent(dir).standardizedFileURL
        guard RecipePaths.isDescendant(url, of: options.workspace) else {
            throw RecipeError.failed("Step dir escapes the workspace: \(dir)")
        }
        return url
    }

    private func mergedEnvironment(recipeEnv: [String: String]?, stepEnv: [String: String]?, vars: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in recipeEnv ?? [:] { env[key] = PromptRenderer.render(value, vars: vars) }
        for (key, value) in stepEnv ?? [:] { env[key] = PromptRenderer.render(value, vars: vars) }
        for (key, value) in vars { env[key] = value }
        return CredentialResolver.resolveEnv(env)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url)
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func timestampForID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
