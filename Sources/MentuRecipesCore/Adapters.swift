import Foundation

public enum CompletionPolicy: Sendable, Equatable {
    case providerCompleteEvent
    case keywordRequired
    case shellExitCode
}

public enum StreamFormat: String, Sendable, Codable {
    case claudeJSON = "claude_json"
    case codexJSON = "codex_json"
    case openAISSE = "openai_sse"
    case plainText = "plain_text"
    case ollamaJSON = "ollama_json"
}

public enum SystemContextHandling: String, Sendable, Codable {
    case native
    case foldedIntoPrompt = "folded_into_prompt"
    case ignored
}

public struct AdapterRequest: Sendable {
    public let prompt: String
    public let systemContext: String?
    public let model: String?
    public let env: [String: String]
    public let timeout: Int
    public let maxOutputBytes: Int
    public let reasoning: String?
    public let thinking: String?
    public let maxOutputTokens: Int?
    public let allowedTools: [String]?
    public let disallowedTools: [String]?
    public let sessionName: String?
    public let workingDirectory: URL

    public init(
        prompt: String,
        systemContext: String? = nil,
        model: String? = nil,
        env: [String: String],
        timeout: Int,
        maxOutputBytes: Int,
        reasoning: String? = nil,
        thinking: String? = nil,
        maxOutputTokens: Int? = nil,
        allowedTools: [String]? = nil,
        disallowedTools: [String]? = nil,
        sessionName: String? = nil,
        workingDirectory: URL
    ) {
        self.prompt = prompt
        self.systemContext = systemContext
        self.model = model
        self.env = env
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
        self.reasoning = reasoning
        self.thinking = thinking
        self.maxOutputTokens = maxOutputTokens
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.sessionName = sessionName
        self.workingDirectory = workingDirectory
    }
}

public struct AdapterResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let providerCompleted: Bool
    public let inputTokens: Int?
    public let outputTokens: Int?
}

public protocol BackendAdapter: Sendable {
    var name: String { get }
    var executionKind: String { get }
    var streamFormat: StreamFormat { get }
    var completionPolicy: CompletionPolicy { get }
    var systemContextHandling: SystemContextHandling { get }
    var isAutoDetectable: Bool { get }
    func isAvailable(env: [String: String]) -> Bool
    func execute(_ request: AdapterRequest, eventSink: @escaping (String) -> Void) async throws -> AdapterResult
}

public enum AdapterRegistry {
    public static func adapter(
        named requestedName: String,
        providers: [String: ProviderConfig] = [:]
    ) -> BackendAdapter? {
        let name = normalize(requestedName)
        if let config = providers[requestedName] ?? providers[name] {
            return adapterFromProviderConfig(name: requestedName, config: config)
        }
        switch name {
        case "shell":
            return ShellAdapter()
        case "openai", "openai-responses", "chatgpt":
            return OpenAIResponsesAdapter()
        case "openai-chat":
            return OpenAIChatAdapter.openAIChat()
        case "deepseek":
            return OpenAIChatAdapter.deepSeek()
        case "ollama":
            return OpenAIChatAdapter.ollama()
        case "claude":
            return ClaudeCLIAdapter()
        case "codex":
            return CodexCLIAdapter()
        default:
            return nil
        }
    }

    public static func autoDetect(env: [String: String]) -> BackendAdapter? {
        let candidates: [BackendAdapter] = [
            OpenAIResponsesAdapter(),
            ClaudeCLIAdapter(),
            CodexCLIAdapter(),
            OpenAIChatAdapter.deepSeek(),
            OpenAIChatAdapter.ollama()
        ]
        return candidates.first { $0.isAutoDetectable && $0.isAvailable(env: env) }
    }

    public static func allAdapters() -> [BackendAdapter] {
        [
            ShellAdapter(),
            OpenAIResponsesAdapter(),
            OpenAIChatAdapter.openAIChat(),
            OpenAIChatAdapter.deepSeek(),
            OpenAIChatAdapter.ollama(),
            ClaudeCLIAdapter(),
            CodexCLIAdapter()
        ]
    }

    private static func adapterFromProviderConfig(name: String, config: ProviderConfig) -> BackendAdapter {
        let api = config.api ?? .chatCompletions
        switch api {
        case .responses:
            return OpenAIResponsesAdapter(
                name: name,
                baseURL: config.baseURL ?? "https://api.openai.com/v1",
                apiKeyEnv: config.apiKeyEnv ?? "OPENAI_API_KEY",
                apiKeyVault: config.apiKeyVault,
                defaultModel: config.model ?? "gpt-5.5"
            )
        case .chatCompletions:
            return OpenAIChatAdapter(
                name: name,
                baseURL: config.baseURL ?? "https://api.openai.com/v1",
                apiKeyEnv: config.apiKeyEnv ?? "OPENAI_API_KEY",
                apiKeyVault: config.apiKeyVault,
                defaultModel: config.model ?? "gpt-4o",
                requiresAuth: true
            )
        case .shell:
            return ShellAdapter()
        case .cli:
            if normalize(name) == "codex" {
                return CodexCLIAdapter()
            }
            return ClaudeCLIAdapter(name: name)
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
