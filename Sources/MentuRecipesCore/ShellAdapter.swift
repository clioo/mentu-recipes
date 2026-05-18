import Foundation

public struct ShellAdapter: BackendAdapter {
    public let name = "shell"
    public let executionKind = "shell"
    public let streamFormat: StreamFormat = .plainText
    public let completionPolicy: CompletionPolicy = .shellExitCode
    public let systemContextHandling: SystemContextHandling = .ignored
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
    public let streamFormat: StreamFormat = .claudeJSON
    public let completionPolicy: CompletionPolicy = .providerCompleteEvent
    public let systemContextHandling: SystemContextHandling = .native
    public let isAutoDetectable = true
    private static let promptSizeThreshold = 7000

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
        var args: [String]
        if request.prompt.utf8.count > Self.promptSizeThreshold,
           let promptFile = try? Self.writeTempPrompt(request.prompt, in: request.workingDirectory) {
            args = ["-p", "Please read and execute the task in \(promptFile.path)"]
        } else {
            args = ["-p", request.prompt]
        }
        args += ["--dangerously-skip-permissions", "--verbose", "--output-format", "stream-json"]

        if let model = request.model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }
        if let reasoning = request.reasoning, !reasoning.isEmpty {
            args.append(contentsOf: ["--effort", reasoning])
        }
        if let thinking = request.thinking, !thinking.isEmpty {
            args.append(contentsOf: ["--thinking", thinking])
        }
        if let systemContext = request.systemContext, !systemContext.isEmpty {
            if let contextFile = try? Self.writeTempPrompt(systemContext, in: request.workingDirectory) {
                args.append(contentsOf: ["--append-system-prompt", "@\(contextFile.path)"])
            } else {
                args.append(contentsOf: ["--append-system-prompt", String(systemContext.prefix(100_000))])
            }
        }
        if let sessionName = request.sessionName, !sessionName.isEmpty {
            args.append(contentsOf: ["--name", sessionName])
        }
        if let allowed = request.allowedTools, !allowed.isEmpty {
            args.append(contentsOf: ["--allowedTools", allowed.joined(separator: ",")])
        }
        let defaultDisallowed = ["TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet"]
        let disallowed = Array(Set(defaultDisallowed + (request.disallowedTools ?? []))).sorted()
        args.append(contentsOf: ["--disallowedTools", disallowed.joined(separator: ",")])

        var parser = ClaudeJSONParser()
        var parsedText = ""
        var providerCompleted = false
        var inputTokens: Int?
        var outputTokens: Int?
        var lastErrorMessage: String?

        let raw = try await ProcessRunner.run(
            executable: executable,
            arguments: args,
            env: Self.agentEnvironment(from: request.env),
            workingDirectory: request.workingDirectory,
            timeout: request.timeout,
            maxOutputBytes: request.maxOutputBytes,
            stdoutSink: { chunk in
                for event in parser.parse(chunk) {
                    switch event {
                    case .text(let text):
                        parsedText += text
                        eventSink(text)
                    case .complete(let input, let output):
                        providerCompleted = true
                        inputTokens = input ?? inputTokens
                        outputTokens = output ?? outputTokens
                    case .error(let message):
                        if lastErrorMessage != message {
                            lastErrorMessage = message
                            eventSink("Error: \(message)\n")
                        }
                    }
                }
            },
            stderrSink: { _ in }
        )

        for event in parser.finish() {
            switch event {
            case .text(let text):
                parsedText += text
                eventSink(text)
            case .complete(let input, let output):
                providerCompleted = true
                inputTokens = input ?? inputTokens
                outputTokens = output ?? outputTokens
            case .error(let message):
                if lastErrorMessage != message {
                    lastErrorMessage = message
                    eventSink("Error: \(message)\n")
                }
            }
        }

        return AdapterResult(
            stdout: parsedText.isEmpty ? raw.stdout : parsedText,
            stderr: Self.sanitizedDiagnostics(raw.stderr),
            exitCode: raw.exitCode,
            providerCompleted: raw.exitCode == 0 && (providerCompleted || parsedText.isEmpty),
            inputTokens: inputTokens,
            outputTokens: outputTokens
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

    private static func writeTempPrompt(_ content: String, in directory: URL) throws -> URL {
        let dir = directory.appendingPathComponent(".mentu/tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("claude-\(UUID().uuidString).md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func sanitizedDiagnostics(_ stderr: String) -> String {
        stderr
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !ProviderLogSanitizer.isSuppressibleAgentDiagnostic($0, backend: "claude") }
            .joined(separator: "\n")
    }
}

public struct ClaudeJSONParser: Sendable {
    public enum Event: Sendable, Equatable {
        case text(String)
        case complete(inputTokens: Int?, outputTokens: Int?)
        case error(String)
    }

    private var pending = ""
    private var emittedText = false

    public init() {}

    public mutating func parse(_ chunk: String) -> [Event] {
        pending += chunk
        var events: [Event] = []
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            events.append(contentsOf: parseLine(line))
        }
        return events
    }

    public mutating func finish() -> [Event] {
        guard !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let line = pending
        pending = ""
        return parseLine(line)
    }

    private mutating func parseLine(_ line: String) -> [Event] {
        let trimmed = ProviderLogSanitizer.clean(line)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else {
            if ProviderLogSanitizer.isSuppressibleAgentDiagnostic(trimmed, backend: "claude") { return [] }
            if let message = ProviderLogSanitizer.userActionableError(trimmed) { return [.error(message)] }
            return []
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let type = object["type"] as? String

        if type == "assistant", let message = object["message"] as? [String: Any] {
            let text = Self.messageContentText(message["content"])
            guard !text.isEmpty else { return [] }
            emittedText = true
            return [.text(text)]
        }

        if type == "result" {
            let usage = object["usage"] as? [String: Any]
            var events: [Event] = []
            if !emittedText, let result = object["result"] as? String, !result.isEmpty {
                events.append(.text(Self.ensureTrailingNewline(result)))
                emittedText = true
            }
            events.append(.complete(
                inputTokens: Self.intValue(usage?["input_tokens"]),
                outputTokens: Self.intValue(usage?["output_tokens"])
            ))
            return events
        }

        if let delta = object["delta"] as? String, !delta.isEmpty {
            emittedText = true
            return [.text(delta)]
        }

        if type == "error" {
            let message = (object["message"] as? String)
                ?? (object["error"] as? String)
                ?? "Claude reported an error"
            return [.error(message)]
        }

        return []
    }

    public static func parseLineForTest(_ line: String) -> [Event] {
        var parser = ClaudeJSONParser()
        return parser.parseLine(line)
    }

    private static func messageContentText(_ raw: Any?) -> String {
        if let value = raw as? String { return value }
        guard let blocks = raw as? [[String: Any]] else { return "" }
        return blocks.compactMap { block in
            guard (block["type"] as? String) == nil || (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }.joined()
    }

    private static func ensureTrailingNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }
}
