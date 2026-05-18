import Foundation

public struct CodexCLIAdapter: BackendAdapter {
    public let name = "codex"
    public let executionKind = "agent-cli"
    public let streamFormat: StreamFormat = .codexJSON
    public let completionPolicy: CompletionPolicy = .providerCompleteEvent
    public let systemContextHandling: SystemContextHandling = .foldedIntoPrompt
    public let isAutoDetectable = true

    public init() {}

    public func isAvailable(env: [String: String]) -> Bool {
        ProcessRunner.findExecutable("codex") != nil
    }

    public func execute(_ request: AdapterRequest, eventSink: @escaping (String) -> Void) async throws -> AdapterResult {
        guard let executable = ProcessRunner.findExecutable("codex") else {
            throw RecipeError.backendUnavailable("codex")
        }

        let prompt = Self.effectivePrompt(request)
        let lastMessage = try? Self.lastMessagePath(in: request.workingDirectory, sessionName: request.sessionName)
        var parser = CodexJSONParser()
        var parsedText = ""
        var inputTokens: Int?
        var outputTokens: Int?
        var providerCompleted = false
        var lastErrorMessage: String?

        var args = [
            "exec",
            "--json",
            "--color", "never",
            "--dangerously-bypass-approvals-and-sandbox",
            "-s", "danger-full-access",
            "-C", request.workingDirectory.path,
            "--skip-git-repo-check"
        ]
        if let model = request.model, !model.isEmpty {
            args += ["--model", model]
        }
        if let reasoning = Self.normalizedReasoningEffort(request.reasoning) {
            args += ["-c", "model_reasoning_effort=\"\(reasoning)\""]
        }
        if let lastMessage {
            args += ["--output-last-message", lastMessage.path]
        }
        args.append(prompt)

        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: args,
            env: Self.agentEnvironment(from: request.env),
            workingDirectory: request.workingDirectory,
            timeout: request.timeout,
            maxOutputBytes: request.maxOutputBytes,
            stdoutSink: { chunk in
                let events = parser.parse(chunk)
                for event in events {
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
            stderrSink: { _ in
                // Codex writes plugin and skill diagnostics to stderr even in JSON mode.
                // Keep the terminal transcript provider-neutral and store stderr only.
            }
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

        if parsedText.isEmpty, let lastMessage, let text = try? String(contentsOf: lastMessage, encoding: .utf8), !text.isEmpty {
            parsedText = text.hasSuffix("\n") ? text : text + "\n"
            eventSink(parsedText)
        }

        return AdapterResult(
            stdout: parsedText.isEmpty ? result.stdout : parsedText,
            stderr: Self.sanitizedDiagnostics(result.stderr),
            exitCode: result.exitCode,
            providerCompleted: result.exitCode == 0 && providerCompleted,
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
            "OPENAI_API_KEY", "CODEX_HOME"
        ]
        for (key, value) in env {
            if exactKeys.contains(key) || key.hasPrefix("LC_") || key.hasPrefix("XDG_") {
                allowed[key] = value
            }
        }
        return allowed
    }

    private static func effectivePrompt(_ request: AdapterRequest) -> String {
        guard let systemContext = request.systemContext, !systemContext.isEmpty else {
            return request.prompt
        }
        return "Context:\n\(systemContext)\n\n---\n\nTask:\n\(request.prompt)"
    }

    private static func normalizedReasoningEffort(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "none", "minimal", "low", "medium", "high", "xhigh":
            return raw.lowercased()
        case "max":
            return "xhigh"
        default:
            return raw.lowercased()
        }
    }

    private static func lastMessagePath(in workspace: URL, sessionName: String?) throws -> URL {
        let dir = workspace.appendingPathComponent(".mentu/tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let label = (sessionName ?? "codex")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return dir.appendingPathComponent("\(label)-last-message.txt")
    }

    private static func sanitizedDiagnostics(_ stderr: String) -> String {
        stderr
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !ProviderLogSanitizer.isSuppressibleAgentDiagnostic($0, backend: "codex") }
            .joined(separator: "\n")
    }
}

public struct CodexJSONParser: Sendable {
    public enum Event: Sendable, Equatable {
        case text(String)
        case complete(inputTokens: Int?, outputTokens: Int?)
        case error(String)
    }

    private var pending = ""

    public init() {}

    public mutating func parse(_ chunk: String) -> [Event] {
        pending += chunk
        var events: [Event] = []
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            events.append(contentsOf: Self.parseLine(line))
        }
        return events
    }

    public mutating func finish() -> [Event] {
        guard !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let line = pending
        pending = ""
        return Self.parseLine(line)
    }

    public static func parseLine(_ line: String) -> [Event] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else {
            if isSuppressibleDiagnostic(trimmed) { return [] }
            if let message = ProviderLogSanitizer.userActionableError(trimmed) {
                return [.error(message)]
            }
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return [] }

        switch type {
        case "item.completed":
            guard let item = json["item"] as? [String: Any],
                  let itemType = item["type"] as? String,
                  ["agent_message", "message"].contains(itemType),
                  let text = stringValue(item["text"] ?? item["message"] ?? item["content"]),
                  !text.isEmpty else { return [] }
            return [.text(ensureTrailingNewline(text))]

        case "turn.completed", "task.complete", "task_complete":
            let usage = json["usage"] as? [String: Any]
            var events: [Event] = []
            if let text = stringValue(json["last_agent_message"]), !text.isEmpty {
                events.append(.text(ensureTrailingNewline(text)))
            }
            events.append(.complete(inputTokens: intValue(usage?["input_tokens"]), outputTokens: intValue(usage?["output_tokens"])))
            return events

        case "event_msg":
            guard let payload = json["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String else { return [] }
            return parsePayload(type: payloadType, payload: payload)

        case "error", "stream_error":
            return [.error(errorMessage(json["message"] ?? json["error"]) ?? "Codex reported an error")]

        default:
            return []
        }
    }

    public static func isSuppressibleDiagnostic(_ line: String) -> Bool {
        ProviderLogSanitizer.isSuppressibleAgentDiagnostic(line, backend: "codex")
    }

    private static func parsePayload(type: String, payload: [String: Any]) -> [Event] {
        switch type {
        case "agent_message", "agent_message_content_delta":
            if let text = stringValue(payload["message"] ?? payload["text"] ?? payload["delta"]), !text.isEmpty {
                return [.text(text)]
            }
        case "task_complete", "turn.completed":
            let usage = payload["usage"] as? [String: Any]
            var events: [Event] = []
            if let text = stringValue(payload["last_agent_message"]), !text.isEmpty {
                events.append(.text(ensureTrailingNewline(text)))
            }
            events.append(.complete(inputTokens: intValue(usage?["input_tokens"]), outputTokens: intValue(usage?["output_tokens"])))
            return events
        case "stream_error", "error":
            return [.error(errorMessage(payload["message"] ?? payload["error"]) ?? "Codex reported an error")]
        default:
            return []
        }
        return []
    }

    private static func ensureTrailingNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String { return value }
        if let value = raw as? NSNumber { return value.stringValue }
        if let array = raw as? [[String: Any]] {
            let parts = array.compactMap { stringValue($0["text"] ?? $0["content"] ?? $0["message"]) }
            return parts.isEmpty ? nil : parts.joined()
        }
        if let dict = raw as? [String: Any] {
            return stringValue(dict["text"] ?? dict["content"] ?? dict["message"] ?? dict["delta"])
        }
        return nil
    }

    private static func errorMessage(_ raw: Any?) -> String? {
        guard let message = stringValue(raw) else { return nil }
        return nestedErrorMessage(message) ?? message
    }

    private static func nestedErrorMessage(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any] {
            return stringValue(error["message"] ?? error["code"] ?? error["type"])
        }
        return stringValue(json["message"] ?? json["error"])
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }
}
