import Foundation

public struct MentuCloudClient: Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let session: URLSession

    public init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public static func configured(baseURL: URL, env: [String: String]) -> MentuCloudClient? {
        let key = env["MENTU_API_KEY"]
            ?? CredentialResolver.resolveSecret(key: "MENTU_API_KEY")
            ?? CredentialResolver.resolveSecret(key: "mentu-api-key")
            ?? CredentialResolver.resolveSecret(key: "mentu-api-token", scope: "api")
        guard let key, !key.isEmpty else { return nil }
        return MentuCloudClient(baseURL: baseURL, apiKey: key)
    }

    public struct StartRunRequest: Codable, Sendable {
        public let recipe_name: String
        public let recipe_kind: String
        public let workspace_id: String?
    }

    public struct StartRunResponse: Codable, Sendable {
        public let runId: String
        public let windowStart: String?
    }

    public struct EndRunRequest: Codable, Sendable {
        public let runId: String
        public let outcome: String
    }

    public struct EndRunResponse: Codable, Sendable {
        public let runId: String
        public let status: String
    }

    public struct EvaluateStepRequest: Codable, Sendable {
        public let run_id: String?
        public let recipe_name: String
        public let step_label: String
        public let backend: String
        public let model: String?
        public let exit_code: Int32
        public let local_complete: Bool
        public let output_tail: String
        public let duration_seconds: Int
    }

    public struct EvaluateStepResponse: Codable, Sendable {
        public let complete: Bool
        public let trust_score: Double?
        public let trust_mode: String?
        public let flags: [String]?
        public let recommendation: String?
    }

    public func startRun(recipeName: String, workspaceID: String?) async throws -> StartRunResponse {
        try await post(
            path: "/v1/recipes/runs/start",
            body: StartRunRequest(recipe_name: recipeName, recipe_kind: "sequence", workspace_id: workspaceID),
            as: StartRunResponse.self
        )
    }

    public func endRun(runId: String, outcome: String) async throws -> EndRunResponse {
        try await post(
            path: "/v1/recipes/runs/end",
            body: EndRunRequest(runId: runId, outcome: outcome),
            as: EndRunResponse.self
        )
    }

    public func evaluateStep(_ body: EvaluateStepRequest) async throws -> EvaluateStepResponse {
        try await post(path: "/v1/recipes/evaluate-step", body: body, as: EvaluateStepResponse.self)
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        as: ResponseBody.Type
    ) async throws -> ResponseBody {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw RecipeError.failed("Invalid Mentu API path: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw RecipeError.failed("Mentu API \(status): \(detail)")
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data)
    }
}
