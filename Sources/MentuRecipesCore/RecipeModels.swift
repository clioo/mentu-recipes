import Foundation

public struct RecipeDefinition: Codable, Sendable {
    public let name: String
    public let description: String?
    public let backend: String?
    public let model: String?
    public let env: [String: String]?
    public let providers: [String: ProviderConfig]?
    public let cloud: CloudRecipeConfig?
    public let steps: [RecipeStep]

    public init(
        name: String,
        description: String? = nil,
        backend: String? = nil,
        model: String? = nil,
        env: [String: String]? = nil,
        providers: [String: ProviderConfig]? = nil,
        cloud: CloudRecipeConfig? = nil,
        steps: [RecipeStep]
    ) {
        self.name = name
        self.description = description
        self.backend = backend
        self.model = model
        self.env = env
        self.providers = providers
        self.cloud = cloud
        self.steps = steps
    }
}

public struct CloudRecipeConfig: Codable, Sendable {
    public let enabled: Bool?
    public let evaluateSteps: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled
        case evaluateSteps = "evaluate_steps"
    }
}

public struct ProviderConfig: Codable, Sendable {
    public let api: ProviderAPI?
    public let baseURL: String?
    public let apiKeyEnv: String?
    public let apiKeyVault: String?
    public let model: String?

    enum CodingKeys: String, CodingKey {
        case api
        case baseURL = "base_url"
        case apiKeyEnv = "api_key_env"
        case apiKeyVault = "api_key_vault"
        case model
    }
}

public enum ProviderAPI: String, Codable, Sendable {
    case responses
    case chatCompletions = "chat_completions"
    case cli
    case shell
}

public struct RecipeStep: Codable, Sendable {
    public let label: String
    public let backend: String?
    public let model: String?
    public let prompt: String?
    public let promptFile: String?
    public let dir: String?
    public let env: [String: String]?
    public let timeout: Int?
    public let completionKeyword: String?
    public let dependsOn: [String]?
    public let maxRetries: Int?
    public let retryBackoffMs: Int?
    public let maxOutputBytes: Int?
    public let reasoning: String?
    public let maxOutputTokens: Int?
    public let verify: VerifyRequirements?

    enum CodingKeys: String, CodingKey {
        case label, backend, model, prompt, dir, env, timeout
        case promptFile = "prompt_file"
        case completionKeyword = "completion_keyword"
        case dependsOn = "depends_on"
        case maxRetries = "max_retries"
        case retryBackoffMs = "retry_backoff_ms"
        case maxOutputBytes = "max_output_bytes"
        case reasoning
        case maxOutputTokens = "max_output_tokens"
        case verify
    }
}

public struct VerifyRequirements: Codable, Sendable {
    public struct GrepPresent: Codable, Sendable {
        public let file: String
        public let pattern: String
        public let min: Int?
        public let max: Int?
        public let description: String?
    }

    public struct GrepAbsent: Codable, Sendable {
        public let file: String
        public let pattern: String
        public let description: String?
    }

    public struct FileAbsent: Codable, Sendable {
        public let file: String
        public let description: String?
    }

    public let grepPresent: [GrepPresent]?
    public let grepAbsent: [GrepAbsent]?
    public let fileAbsent: [FileAbsent]?
    public let gitCleanOutside: [String]?

    enum CodingKeys: String, CodingKey {
        case grepPresent = "grep_present"
        case grepAbsent = "grep_absent"
        case fileAbsent = "file_absent"
        case gitCleanOutside = "git_clean_outside"
    }
}

public struct RunOptions: Sendable {
    public let workspace: URL
    public let home: URL
    public let backend: String?
    public let model: String?
    public let vars: [String: String]
    public let cloudEnabled: Bool
    public let cloudBaseURL: URL
    public let quiet: Bool

    public init(
        workspace: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        backend: String? = nil,
        model: String? = nil,
        vars: [String: String] = [:],
        cloudEnabled: Bool = true,
        cloudBaseURL: URL = URL(string: "https://api.mentu.ai")!,
        quiet: Bool = false
    ) {
        self.workspace = workspace
        self.home = home
        self.backend = backend
        self.model = model
        self.vars = vars
        self.cloudEnabled = cloudEnabled
        self.cloudBaseURL = cloudBaseURL
        self.quiet = quiet
    }
}

public enum RecipeError: Error, CustomStringConvertible {
    case recipeNotFound(String)
    case invalidRecipe(String)
    case missingPrompt(label: String)
    case missingBackend(label: String)
    case backendUnavailable(String)
    case dependencyCycle
    case duplicateStep(String)
    case failed(String)

    public var description: String {
        switch self {
        case .recipeNotFound(let name): return "Recipe not found: \(name)"
        case .invalidRecipe(let message): return "Invalid recipe: \(message)"
        case .missingPrompt(let label): return "Step '\(label)' has no prompt or prompt_file"
        case .missingBackend(let label): return "Step '\(label)' has no backend and no neutral backend is available"
        case .backendUnavailable(let name): return "Backend unavailable: \(name)"
        case .dependencyCycle: return "Recipe dependency graph contains a cycle"
        case .duplicateStep(let label): return "Duplicate step label: \(label)"
        case .failed(let message): return message
        }
    }
}
