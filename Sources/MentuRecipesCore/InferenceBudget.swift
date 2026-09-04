import Foundation

public struct InferenceBudget: Codable, Sendable, Equatable {
    public let maxRequests: Int
    public let maxConcurrentRequests: Int
    public let maxRequestBytes: Int
    public let maxTotalInputBytes: Int
    public let maxOutputTokens: Int
    public let maxDurationSeconds: Int

    public init(maxRequests: Int, maxConcurrentRequests: Int = 1, maxRequestBytes: Int,
                maxTotalInputBytes: Int, maxOutputTokens: Int, maxDurationSeconds: Int) {
        self.maxRequests = maxRequests
        self.maxConcurrentRequests = maxConcurrentRequests
        self.maxRequestBytes = maxRequestBytes
        self.maxTotalInputBytes = maxTotalInputBytes
        self.maxOutputTokens = maxOutputTokens
        self.maxDurationSeconds = maxDurationSeconds
    }

    public func validate() throws {
        guard maxRequests > 0, maxRequests <= 1_000_000,
              maxConcurrentRequests > 0, maxConcurrentRequests <= maxRequests,
              maxRequestBytes > 0, maxRequestBytes <= 16_777_216,
              maxTotalInputBytes >= maxRequestBytes, maxTotalInputBytes <= 9_007_199_254_740_991,
              maxOutputTokens > 0, maxOutputTokens <= 2_147_483_647,
              maxDurationSeconds > 0, maxDurationSeconds <= 604_800 else {
            throw RecipeError.invalidRecipe("Inference budget limits must be positive and internally consistent")
        }
    }

    enum CodingKeys: String, CodingKey {
        case maxRequests = "max_requests"
        case maxConcurrentRequests = "max_concurrent_requests"
        case maxRequestBytes = "max_request_bytes"
        case maxTotalInputBytes = "max_total_input_bytes"
        case maxOutputTokens = "max_output_tokens"
        case maxDurationSeconds = "max_duration_seconds"
    }
}

public struct InferenceBudgetContext: Codable, Sendable, Equatable {
    public let limits: InferenceBudget
    public let directory: URL
    public let startedAtMillis: Int64

    public init(limits: InferenceBudget, directory: URL, startedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.limits = limits
        self.directory = directory
        self.startedAtMillis = startedAtMillis
    }
}

public enum ChatCompletionTokenField: String, Codable, Sendable {
    case maxTokens = "max_tokens"
    case maxCompletionTokens = "max_completion_tokens"
}
