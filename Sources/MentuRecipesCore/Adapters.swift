import Foundation

public enum CompletionPolicy: Sendable, Equatable {
    case providerCompleteEvent
    case keywordRequired
    case shellExitCode
}

public struct AdapterRequest: Sendable {
    public let prompt: String
    public let systemContext: String?
    public let model: String?
    public let env: [String: String]
    public let timeout: Int
    public let maxOutputBytes: Int
    public let reasoning: String?
    public let maxOutputTokens: Int?
    public let workingDirectory: URL
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
    var completionPolicy: CompletionPolicy { get }
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
        default:
            return nil
        }
    }

    public static func autoDetect(env: [String: String]) -> BackendAdapter? {
        let candidates: [BackendAdapter] = [
            OpenAIResponsesAdapter(),
            ClaudeCLIAdapter(),
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
            ClaudeCLIAdapter()
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
            return ClaudeCLIAdapter(name: name)
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
