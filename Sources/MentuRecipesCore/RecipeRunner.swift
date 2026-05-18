import Foundation

public struct StepRunRecord: Codable, Sendable {
    public let label: String
    public let backend: String
    public let model: String?
    public let exitCode: Int32
    public let completionMethod: String?
    public let localComplete: Bool
    public let cloudComplete: Bool?
    public let trustScore: Double?
    public let durationSeconds: Int
    public let attempts: Int
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let outputFile: String
    public let errorFile: String
    public let git: StepGitRecord?
    public let hooks: [HookRunRecord]?

    enum CodingKeys: String, CodingKey {
        case label, backend, model
        case exitCode = "exit_code"
        case completionMethod = "completion_method"
        case localComplete = "local_complete"
        case cloudComplete = "cloud_complete"
        case trustScore = "trust_score"
        case durationSeconds = "duration_seconds"
        case attempts
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case outputFile = "output_file"
        case errorFile = "error_file"
        case git, hooks
    }
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
    public var hooks: [HookRunRecord]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case recipeName = "recipe_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case outcome
        case cloudRunId = "cloud_run_id"
        case cloudMode = "cloud_mode"
        case steps, hooks
    }
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
        let runId = "run_\(Self.timestampForID())_\(UUID().uuidString.prefix(8))"
        let runDir = paths.projectRuns.appendingPathComponent(runId)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let baseEnv = mergedEnvironment(recipeEnv: recipe.env, stepEnv: nil, vars: options.vars)
        let cloudRequested = options.cloudEnabled || recipe.cloud?.enabled == true
        let cloud = cloudRequested
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
            steps: [],
            hooks: []
        )
        try write(record, to: runDir.appendingPathComponent("run.json"))

        record.hooks += await HookRunner.run(
            event: "before_run",
            commands: recipe.hooks?.beforeRun,
            recipe: recipe,
            step: nil,
            runId: runId,
            runDir: runDir,
            workspace: options.workspace,
            status: "running",
            quiet: options.quiet
        )

        if let cloud {
            do {
                let start = try await cloud.startRun(recipeName: recipe.name, workspaceID: options.workspace.lastPathComponent)
                record.cloudRunId = start.runId
                try write(record, to: runDir.appendingPathComponent("run.json"))
            } catch {
                record.cloudMode = "unavailable"
            }
        }

        let overallOK = try await runBody(recipe, runDir: runDir, cloud: cloud, record: &record)

        record.outcome = overallOK ? "ok" : "failed"
        record.endedAt = Self.isoNow()
        record.hooks += await HookRunner.run(
            event: "after_run",
            commands: recipe.hooks?.afterRun,
            recipe: recipe,
            step: nil,
            runId: runId,
            runDir: runDir,
            workspace: options.workspace,
            status: record.outcome,
            quiet: options.quiet
        )
        if let cloudRunId = record.cloudRunId, let cloud {
            _ = try? await cloud.endRun(runId: cloudRunId, outcome: record.outcome)
        }
        try write(record, to: runDir.appendingPathComponent("run.json"))
        return record
    }

    private func runBody(
        _ recipe: RecipeDefinition,
        runDir: URL,
        cloud: MentuCloudClient?,
        record: inout RecipeRunRecord
    ) async throws -> Bool {
        switch recipe.type ?? .sequence {
        case .sequence, .formula:
            return try await runSteps(recipe, runDir: runDir, cloud: cloud, record: &record)
        case .pipeline:
            return try await runRecipeNodes(recipe.recipes ?? [], recipe: recipe, runDir: runDir, record: &record, parallel: false)
        case .compound:
            return try await runRecipeDAG(recipe.recipes ?? [], recipe: recipe, runDir: runDir, record: &record)
        case .parallel:
            return try await runRecipeNodes(recipe.recipes ?? [], recipe: recipe, runDir: runDir, record: &record, parallel: true)
        }
    }

    private func runSteps(
        _ recipe: RecipeDefinition,
        runDir: URL,
        cloud: MentuCloudClient?,
        record: inout RecipeRunRecord
    ) async throws -> Bool {
        let hasDAG = recipe.steps.contains { !($0.dependsOn ?? []).isEmpty }
        if !hasDAG {
            var overallOK = true
            for step in try store.topologicalOrder(recipe.steps) {
                let stepRecord = await runStepSafely(step, recipe: recipe, runDir: runDir, cloud: cloud, cloudRunId: record.cloudRunId)
                record.steps.append(stepRecord)
                try write(record, to: runDir.appendingPathComponent("run.json"))
                if !(stepRecord.cloudComplete ?? stepRecord.localComplete) {
                    overallOK = false
                    break
                }
            }
            return overallOK
        }

        var completed: [String: Bool] = [:]
        var overallOK = true
        for wave in try stepWaves(recipe.steps) {
            let runnable = wave.filter { step in
                (step.dependsOn ?? []).allSatisfy { completed[$0] == true }
            }
            let skipped = wave.filter { step in !runnable.contains(where: { $0.label == step.label }) }
            for step in skipped {
                completed[step.label] = false
                record.steps.append(failedRecord(step, recipe: recipe, message: "dependency failed or skipped"))
                overallOK = false
            }
            let results = await runStepWave(runnable, recipe: recipe, runDir: runDir, cloud: cloud, cloudRunId: record.cloudRunId)
            for stepRecord in results {
                completed[stepRecord.label] = stepRecord.cloudComplete ?? stepRecord.localComplete
                if completed[stepRecord.label] != true { overallOK = false }
                record.steps.append(stepRecord)
            }
            try write(record, to: runDir.appendingPathComponent("run.json"))
            if !overallOK { break }
        }
        return overallOK
    }

    private func runStepWave(
        _ steps: [RecipeStep],
        recipe: RecipeDefinition,
        runDir: URL,
        cloud: MentuCloudClient?,
        cloudRunId: String?
    ) async -> [StepRunRecord] {
        let limit = max(1, options.maxParallel ?? recipe.maxParallel ?? steps.count)
        let semaphore = AsyncSemaphore(value: limit)
        return await withTaskGroup(of: StepRunRecord.self) { group in
                for step in steps {
                    group.addTask {
                        await semaphore.wait()
                    let record = await self.runStepSafely(step, recipe: recipe, runDir: runDir, cloud: cloud, cloudRunId: cloudRunId)
                    await semaphore.signal()
                    return record
                }
            }
            var records: [StepRunRecord] = []
            for await record in group {
                records.append(record)
            }
            return records.sorted { $0.label < $1.label }
        }
    }

    private func runStepSafely(
        _ step: RecipeStep,
        recipe: RecipeDefinition,
        runDir: URL,
        cloud: MentuCloudClient?,
        cloudRunId: String?
    ) async -> StepRunRecord {
        do {
            return try await runStep(step, recipe: recipe, runDir: runDir, cloud: cloud, cloudRunId: cloudRunId)
        } catch {
            let message = cleanErrorMessage(String(describing: error))
            if !options.quiet {
                FileHandle.standardOutput.write(Data("Error: \(message)\n".utf8))
            }
            let failed = failedRecord(step, recipe: recipe, message: message)
            try? "".write(to: runDir.appendingPathComponent(failed.outputFile), atomically: true, encoding: .utf8)
            try? (message + "\n").write(to: runDir.appendingPathComponent(failed.errorFile), atomically: true, encoding: .utf8)
            _ = await HookRunner.run(
                event: "on_error",
                commands: recipe.hooks?.onError,
                recipe: recipe,
                step: step,
                runId: runDir.lastPathComponent,
                runDir: runDir,
                workspace: options.workspace,
                status: "failed",
                quiet: options.quiet
            )
            return failed
        }
    }

    private func cleanErrorMessage(_ message: String) -> String {
        var text = ProviderLogSanitizer.clean(message)
        if text.hasPrefix("failed(\""), text.hasSuffix("\")") {
            text.removeFirst("failed(\"".count)
            text.removeLast(2)
            text = text.replacingOccurrences(of: #"\""#, with: #"""#)
        }
        return text
    }

    private func failedRecord(_ step: RecipeStep, recipe: RecipeDefinition, message: String) -> StepRunRecord {
        StepRunRecord(
            label: step.label,
            backend: step.backend ?? options.backend ?? recipe.backend ?? "unresolved",
            model: step.model ?? options.model ?? recipe.model,
            exitCode: 1,
            completionMethod: "failed",
            localComplete: false,
            cloudComplete: nil,
            trustScore: nil,
            durationSeconds: 0,
            attempts: 0,
            inputTokens: nil,
            outputTokens: nil,
            outputFile: "\(step.label).stdout",
            errorFile: "\(step.label).stderr",
            git: nil,
            hooks: nil
        )
    }

    private func stepWaves(_ steps: [RecipeStep]) throws -> [[RecipeStep]] {
        let ordered = try store.topologicalOrder(steps)
        var levels: [String: Int] = [:]
        let byLabel = Dictionary(uniqueKeysWithValues: ordered.map { ($0.label, $0) })
        func level(_ label: String) -> Int {
            if let cached = levels[label] { return cached }
            let deps = byLabel[label]?.dependsOn ?? []
            let value = deps.isEmpty ? 0 : ((deps.map(level).max() ?? 0) + 1)
            levels[label] = value
            return value
        }
        for step in ordered { _ = level(step.label) }
        return Dictionary(grouping: ordered, by: { levels[$0.label] ?? 0 })
            .keys.sorted()
            .map { key in ordered.filter { (levels[$0.label] ?? 0) == key } }
    }

    private func runRecipeNodes(
        _ nodes: [RecipeNode],
        recipe: RecipeDefinition,
        runDir: URL,
        record: inout RecipeRunRecord,
        parallel: Bool
    ) async throws -> Bool {
        if parallel {
            let limit = max(1, options.maxParallel ?? recipe.maxParallel ?? nodes.count)
            let semaphore = AsyncSemaphore(value: limit)
            let results = await withTaskGroup(of: StepRunRecord.self) { group in
                for node in nodes {
                    group.addTask {
                        await semaphore.wait()
                        let record = await self.runChildRecipe(node, parent: recipe, runDir: runDir)
                        await semaphore.signal()
                        return record
                    }
                }
                var records: [StepRunRecord] = []
                for await record in group { records.append(record) }
                return records
            }
            record.steps += results.sorted { $0.label < $1.label }
            try write(record, to: runDir.appendingPathComponent("run.json"))
            return results.allSatisfy(\.localComplete)
        }

        var ok = true
        for node in nodes {
            let result = await runChildRecipe(node, parent: recipe, runDir: runDir)
            record.steps.append(result)
            try write(record, to: runDir.appendingPathComponent("run.json"))
            if !result.localComplete {
                ok = false
                break
            }
        }
        return ok
    }

    private func runRecipeDAG(
        _ nodes: [RecipeNode],
        recipe: RecipeDefinition,
        runDir: URL,
        record: inout RecipeRunRecord
    ) async throws -> Bool {
        let ordered = try store.topologicalOrder(nodes)
        var completed: [String: Bool] = [:]
        var ok = true
        for node in ordered {
            let label = node.label ?? node.recipe
            guard (node.dependsOn ?? []).allSatisfy({ completed[$0] == true }) else {
                completed[label] = false
                ok = false
                continue
            }
            let result = await runChildRecipe(node, parent: recipe, runDir: runDir)
            completed[label] = result.localComplete
            record.steps.append(result)
            try write(record, to: runDir.appendingPathComponent("run.json"))
            if !result.localComplete { ok = false }
        }
        return ok
    }

    private func runChildRecipe(_ node: RecipeNode, parent: RecipeDefinition, runDir: URL) async -> StepRunRecord {
        let label = node.label ?? node.recipe
        let start = Date()
        var childVars = options.vars
        for (key, value) in node.vars ?? [:] { childVars[key] = value }
        let child = RecipeRunner(options: RunOptions(
            workspace: options.workspace,
            home: options.home,
            backend: options.backend,
            model: options.model,
            vars: childVars,
            cloudEnabled: options.cloudEnabled,
            cloudBaseURL: options.cloudBaseURL,
            quiet: options.quiet,
            maxParallel: options.maxParallel
        ))
        do {
            let childRecord = try await child.run(node.recipe)
            let outputFile = "\(label).child-run.txt"
            try? childRecord.runId.write(to: runDir.appendingPathComponent(outputFile), atomically: true, encoding: .utf8)
            return StepRunRecord(
                label: label,
                backend: "recipe",
                model: nil,
                exitCode: childRecord.outcome == "ok" ? 0 : 1,
                completionMethod: "child_recipe",
                localComplete: childRecord.outcome == "ok",
                cloudComplete: nil,
                trustScore: nil,
                durationSeconds: Int(Date().timeIntervalSince(start)),
                attempts: 1,
                inputTokens: nil,
                outputTokens: nil,
                outputFile: outputFile,
                errorFile: "\(label).child-run.err",
                git: nil,
                hooks: nil
            )
        } catch {
            let errorFile = "\(label).child-run.err"
            try? String(describing: error).write(to: runDir.appendingPathComponent(errorFile), atomically: true, encoding: .utf8)
            return StepRunRecord(
                label: label,
                backend: "recipe",
                model: nil,
                exitCode: 1,
                completionMethod: "child_recipe",
                localComplete: false,
                cloudComplete: nil,
                trustScore: nil,
                durationSeconds: Int(Date().timeIntervalSince(start)),
                attempts: 1,
                inputTokens: nil,
                outputTokens: nil,
                outputFile: "\(label).child-run.txt",
                errorFile: errorFile,
                git: nil,
                hooks: nil
            )
        }
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
        var hookRecords: [HookRunRecord] = []
        hookRecords += await HookRunner.run(
            event: "before_step",
            commands: recipe.hooks?.beforeStep,
            recipe: recipe,
            step: step,
            runId: runDir.lastPathComponent,
            runDir: runDir,
            workspace: stepDir,
            status: "running",
            quiet: options.quiet
        )

        for attempt in 1...attemptsAllowed {
            attempts = attempt
            if !options.quiet {
                FileHandle.standardOutput.write(Data("▶ \(step.label) · \(adapter.name)\n".utf8))
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
                    thinking: step.thinking,
                    maxOutputTokens: step.maxOutputTokens,
                    allowedTools: step.allowedTools,
                    disallowedTools: step.disallowedTools,
                    sessionName: "mentu-recipes-\(recipe.name)-\(step.label)",
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

        let completionMethod: String
        if let keyword = step.completionKeyword, !keyword.isEmpty, lastLocalComplete {
            completionMethod = "keyword_output"
        } else {
            switch adapter.completionPolicy {
            case .shellExitCode: completionMethod = "exit_code"
            case .providerCompleteEvent: completionMethod = "provider_complete"
            case .keywordRequired: completionMethod = "keyword_required"
            }
        }

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

        var gitRecord: StepGitRecord?
        if lastLocalComplete {
            gitRecord = await GitWorkspace.finalizeStep(
                label: step.label,
                expectedChanges: step.expectedChanges,
                stepDir: stepDir,
                runDir: runDir,
                runId: runDir.lastPathComponent
            )
        }

        hookRecords += await HookRunner.run(
            event: lastLocalComplete ? "after_step" : "on_error",
            commands: lastLocalComplete ? recipe.hooks?.afterStep : recipe.hooks?.onError,
            recipe: recipe,
            step: step,
            runId: runDir.lastPathComponent,
            runDir: runDir,
            workspace: stepDir,
            status: lastLocalComplete ? "ok" : "failed",
            extraEnv: [
                "MENTU_RECIPES_STEP_STDOUT": runDir.appendingPathComponent(stdoutFile).path,
                "MENTU_RECIPES_STEP_STDERR": runDir.appendingPathComponent(stderrFile).path
            ],
            quiet: options.quiet
        )

        return StepRunRecord(
            label: step.label,
            backend: adapter.name,
            model: model,
            exitCode: result.exitCode,
            completionMethod: completionMethod,
            localComplete: lastLocalComplete,
            cloudComplete: cloudComplete,
            trustScore: trustScore,
            durationSeconds: Int(Date().timeIntervalSince(start)),
            attempts: attempts,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
            outputFile: stdoutFile,
            errorFile: stderrFile,
            git: gitRecord,
            hooks: hookRecords
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
