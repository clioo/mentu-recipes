import Foundation

public struct ShellAdapter: BackendAdapter {
    public let name = "shell"
    public let executionKind = "shell"
    public let completionPolicy: CompletionPolicy = .shellExitCode
    public let isAutoDetectable = false

    public init() {}

    public func isAvailable(env: [String: String]) -> Bool {
        FileManager.default.isExecutableFile(atPath: "/bin/sh")
    }

    public func execute(_ request: AdapterRequest, eventSink: @escaping (String) -> Void) async throws -> AdapterResult {
        try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", request.prompt],
            env: request.env,
            workingDirectory: request.workingDirectory,
            timeout: request.timeout,
            maxOutputBytes: request.maxOutputBytes,
            eventSink: eventSink
        )
    }
}

public struct ClaudeCLIAdapter: BackendAdapter {
    public let name: String
    public let executionKind = "agent-cli"
    public let completionPolicy: CompletionPolicy = .keywordRequired
    public let isAutoDetectable = true

    public init(name: String = "claude") {
        self.name = name
    }

    public func isAvailable(env: [String: String]) -> Bool {
        ProcessRunner.findExecutable("claude") != nil
    }

    public func execute(_ request: AdapterRequest, eventSink: @escaping (String) -> Void) async throws -> AdapterResult {
        guard let executable = ProcessRunner.findExecutable("claude") else {
            throw RecipeError.backendUnavailable("claude")
        }
        var args = ["-p", request.prompt]
        if let model = request.model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }
        if let reasoning = request.reasoning, !reasoning.isEmpty {
            args.append(contentsOf: ["--effort", reasoning])
        }
        if let systemContext = request.systemContext, !systemContext.isEmpty {
            args.append(contentsOf: ["--append-system-prompt", systemContext])
        }
        return try await ProcessRunner.run(
            executable: executable,
            arguments: args,
            env: Self.agentEnvironment(from: request.env),
            workingDirectory: request.workingDirectory,
            timeout: request.timeout,
            maxOutputBytes: request.maxOutputBytes,
            eventSink: eventSink
        )
    }

    public static func agentEnvironment(from env: [String: String]) -> [String: String] {
        var allowed: [String: String] = [:]
        let exactKeys: Set<String> = [
            "PATH", "HOME", "SHELL", "USER", "LOGNAME", "TMPDIR", "TMP", "TEMP",
            "TERM", "LANG", "LC_ALL", "SSL_CERT_FILE", "SSL_CERT_DIR",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "ANTHROPIC_API_KEY"
        ]
        for (key, value) in env {
            if exactKeys.contains(key)
                || key.hasPrefix("LC_")
                || key.hasPrefix("XDG_") {
                allowed[key] = value
            }
        }
        return allowed
    }
}
