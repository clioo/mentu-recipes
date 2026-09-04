import Foundation

public struct PiCLIAdapter: BackendAdapter {
    public let name: String
    public let executionKind = "agent-cli"
    public let streamFormat: StreamFormat = .piJSON
    public let completionPolicy: CompletionPolicy = .providerCompleteEvent
    public let systemContextHandling: SystemContextHandling = .native
    public let isAutoDetectable = false
    private let config: ProviderConfig?

    public init(name: String = "pi", config: ProviderConfig? = nil) {
        self.name = name
        self.config = config
    }

    public var capabilities: AdapterCapability {
        AdapterCapability(name: name, executionKind: executionKind, streamFormat: streamFormat,
            completionPolicy: "provider_complete_event", systemContextHandling: systemContextHandling,
            isLocal: true, requiresNetwork: true, requiresCredential: true, supportsTools: true,
            supportsToolAllowList: true, supportsToolDenyList: true, supportsReasoning: false,
            supportsThinking: false, supportsMaxOutputTokens: true, reportsTokenUsage: true,
            supportsStructuredCompletion: true, canRunOffline: false)
    }

    public func isAvailable(env: [String: String]) -> Bool {
        ProcessRunner.findExecutable("pi") != nil && ProcessRunner.findExecutable("node") != nil
    }

    public func execute(_ request: AdapterRequest, eventSink: @escaping (String) -> Void) async throws -> AdapterResult {
        guard let config, let baseURL = config.baseURL,
              let model = request.model ?? config.model, !model.isEmpty else {
            throw RecipeError.failed("Pi requires an explicit provider with api pi, base_url, and exact model ID")
        }
        guard let budget = request.inferenceBudget else { throw RecipeError.failed("Pi requires an explicit inference_budget") }
        try budget.limits.validate()
        try ProviderCredentialPolicy.validateDestination(name: name, baseURL: baseURL,
            apiKeyEnv: config.apiKeyEnv ?? "", apiKeyVault: config.apiKeyVault)
        guard request.reasoning == nil, request.thinking == nil || request.thinking == "off" else {
            throw RecipeError.failed("The bounded Pi transport does not support reasoning/thinking overrides")
        }
        guard let pi = ProcessRunner.findExecutable("pi"), let node = ProcessRunner.findExecutable("node") else {
            throw RecipeError.backendUnavailable("Pi and Node.js 22.19 or newer are required")
        }
        try await Self.requireVersion(executable: pi, minimum: [0, 84, 1], env: request.env, workspace: request.workingDirectory)
        try await Self.requireVersion(executable: node, minimum: [22, 19, 0], env: request.env, workspace: request.workingDirectory)
        let skills = try (config.skills ?? []).map { value -> String in
            let url = RecipePaths(workspace: request.workingDirectory).expand(value).standardizedFileURL.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: url.path) else { throw RecipeError.failed("Configured Pi skill is unavailable") }
            return url.path
        }
        guard config.contextWindow ?? 32768 > 0 else { throw RecipeError.failed("Pi context window must be positive") }
        let tools = Set(["read", "bash", "edit", "write", "grep", "find", "ls"])
        let allowed = request.allowedTools ?? ["read", "bash", "edit", "write"]
        let denied = request.disallowedTools ?? []
        guard (allowed + denied).allSatisfy(tools.contains), request.maxOutputTokens ?? 1 > 0 else {
            throw RecipeError.failed("Invalid Pi tool policy or output token limit")
        }
        let key = config.apiKeyEnv.flatMap { request.env[$0] }
            ?? config.apiKeyVault.flatMap { CredentialResolver.resolveSecret(key: $0) }
        guard let key, !key.isEmpty else { throw RecipeError.failed("The configured Pi provider credential is unavailable") }
        let attemptDir = budget.directory.appendingPathComponent("pi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: attemptDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Self.writeRuntime(to: attemptDir)
        let launch: [String: Any] = [
            "base_url": baseURL, "model": model, "pi_executable": pi,
            "max_tokens_field": (config.maxTokensField ?? .maxTokens).rawValue,
            "context_window": config.contextWindow ?? 32768,
            "budget_directory": budget.directory.path, "attempt_directory": attemptDir.path,
            "started_at_ms": budget.startedAtMillis,
            "limits": try JSONSerialization.jsonObject(with: JSONEncoder().encode(budget.limits)),
            "max_output_tokens": min(request.maxOutputTokens ?? budget.limits.maxOutputTokens, budget.limits.maxOutputTokens),
            "max_response_bytes": max(1_048_576, request.maxOutputBytes),
            "request_timeout_ms": min(max(1, request.timeout), budget.limits.maxDurationSeconds) * 1000,
            "timeout_ms": min(max(1, request.timeout), budget.limits.maxDurationSeconds) * 1000,
            "workspace": request.workingDirectory.path, "prompt": request.prompt,
            "allowed_tools": allowed, "disallowed_tools": denied, "skill_files": skills,
            "system_context": request.systemContext ?? ""
        ]
        let launchURL = attemptDir.appendingPathComponent("launch.json")
        try JSONSerialization.data(withJSONObject: launch, options: [.sortedKeys]).write(to: launchURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: launchURL.path)
        var env = Self.runtimeEnvironment(request.env)
        env["MENTU_PI_TARGET_KEY"] = key
        let parser = PiStreamCollector(maxBytes: request.maxOutputBytes)
        let result = try await ProcessRunner.run(executable: node,
            arguments: [attemptDir.appendingPathComponent("launch.mjs").path, launchURL.path],
            env: env, workingDirectory: request.workingDirectory,
            timeout: min(max(1, request.timeout), budget.limits.maxDurationSeconds) + 5,
            maxOutputBytes: request.maxOutputBytes,
            stdoutSink: { chunk in parser.append(chunk).forEach(eventSink) }, stderrSink: { _ in })
        let parsed = parser.finish()
        let evidenceURL = attemptDir.appendingPathComponent("inference.json")
        let evidence = (try? Data(contentsOf: evidenceURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let complete = result.exitCode == 0 && parsed.completed && !parsed.failed && evidence?["exit_code"] as? Int == 0
        let diagnostics = complete ? result.stderr : result.stderr + "\nPi did not produce a verified completion. Inspect \(attemptDir.path) and the shared budget evidence.\n"
        return AdapterResult(stdout: parsed.text, stderr: diagnostics,
            exitCode: complete ? 0 : (result.exitCode == 0 ? 1 : result.exitCode), providerCompleted: complete,
            inputTokens: evidence?["input_tokens"] as? Int, outputTokens: evidence?["output_tokens"] as? Int)
    }

    static func writeRuntime(to directory: URL) throws {
        for (file, source) in [("budget.mjs", PiBudgetRuntime.source), ("gateway.mjs", PiGatewayRuntime.source), ("launch.mjs", PiLaunchRuntime.source)] {
            try source.write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
    }

    static func runtimeEnvironment(_ input: [String: String]) -> [String: String] {
        let keys: Set<String> = ["PATH", "HOME", "SHELL", "USER", "LOGNAME", "TMPDIR", "TMP", "TEMP", "LANG", "LC_ALL"]
        return input.filter { keys.contains($0.key) }
    }

    private static func requireVersion(executable: String, minimum: [Int], env: [String: String], workspace: URL) async throws {
        var environment = runtimeEnvironment(env)
        environment["PI_OFFLINE"] = "1"
        environment["PI_TELEMETRY"] = "0"
        let result = try await ProcessRunner.run(executable: executable, arguments: ["--version"], env: environment,
            workingDirectory: workspace, timeout: 5, maxOutputBytes: 1000, eventSink: { _ in })
        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^v", with: "", options: .regularExpression)
        let parts = raw.split(separator: ".").compactMap { Int($0) }
        guard result.exitCode == 0, parts.count == 3, !parts.lexicographicallyPrecedes(minimum) else {
            throw RecipeError.failed("Unsupported Pi/Node runtime version; Pi 0.84.1+ and Node 22.19+ are required")
        }
    }
}

private final class PiStreamCollector {
    private let lock = NSLock()
    private var parser: PiJSONParser
    init(maxBytes: Int) { parser = PiJSONParser(maxBytes: maxBytes) }
    func append(_ chunk: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return parser.parse(chunk)
    }
    func finish() -> PiJSONParser {
        lock.lock(); defer { lock.unlock() }
        parser.finish()
        return parser
    }
}
