import Foundation

public enum ProviderLogSanitizer {
    public static func clean(_ line: String) -> String {
        line
            .replacingOccurrences(
                of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isSuppressibleAgentDiagnostic(_ line: String, backend: String) -> Bool {
        let cleaned = clean(line)
        guard !cleaned.isEmpty else { return true }

        if cleaned == "Reading additional input from stdin..." { return true }
        if cleaned == "--------" { return true }
        if backend == "codex", cleaned == "user" { return true }
        if cleaned.hasPrefix("<html>") { return true }
        if cleaned.hasPrefix("data:") || cleaned.hasPrefix("event:") { return true }

        let metadataPrefixes = [
            "OpenAI Codex v",
            "workdir:",
            "model:",
            "provider:",
            "approval:",
            "sandbox:",
            "reasoning effort:",
            "reasoning summaries:",
            "session id:",
            "hook:"
        ]
        if metadataPrefixes.contains(where: { cleaned.hasPrefix($0) }) { return true }

        let noisyFragments = [
            "failed to load skill",
            "invalid description: exceeds maximum length",
            "ignoring interface.icon_",
            "ignoring interface.defaultPrompt",
            "failed to warm featured plugin ids cache",
            "startup websocket prewarm setup failed",
            "failed to initialize MCP client during shutdown",
            "Failed to terminate MCP process group",
            "Assembling the plan",
            "Cleaning up (agent completed"
        ]
        if noisyFragments.contains(where: { cleaned.contains($0) }) { return true }

        if userActionableError(cleaned) != nil { return false }
        if timestampedProviderLog(cleaned) { return true }

        let lower = cleaned.lowercased()
        return lower.hasPrefix("debug ") || lower.hasPrefix("warn ")
    }

    public static func userActionableError(_ line: String) -> String? {
        let cleaned = clean(line)
        let lower = cleaned.lowercased()
        let actionable = [
            "api key",
            "unauthorized",
            "forbidden",
            "authentication",
            "auth is missing",
            "login is required",
            "rate limit",
            "quota",
            "insufficient_quota",
            "billing",
            "invalid_request_error",
            "not supported"
        ]
        guard cleaned.hasPrefix("Error:") || cleaned.hasPrefix("ERROR:") || actionable.contains(where: { lower.contains($0) }) else {
            return nil
        }
        return cleaned
    }

    private static func timestampedProviderLog(_ line: String) -> Bool {
        line.range(
            of: #"^\d{4}-\d{2}-\d{2}T.*\s+(TRACE|DEBUG|INFO|WARN|ERROR)\s+(codex|claude|anthropic|openai|gemini|cursor|ollama)[A-Za-z0-9_:\.-]*"#,
            options: .regularExpression
        ) != nil
    }
}
