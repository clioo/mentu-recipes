import Foundation

public struct PiJSONParser {
    public private(set) var text = ""
    public private(set) var completed = false
    public private(set) var failed = false
    public private(set) var toolCalls: [String] = []
    private var pending = ""
    private let maxBytes: Int

    public init(maxBytes: Int = 5_000_000) { self.maxBytes = max(1, maxBytes) }

    public mutating func parse(_ chunk: String) -> [String] {
        pending += chunk
        guard pending.utf8.count <= max(maxBytes, 1_048_576) else {
            failed = true; pending = ""; return []
        }
        var deltas: [String] = []
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newline])
            pending.removeSubrange(...newline)
            if let delta = consume(line) { deltas.append(delta) }
        }
        return deltas
    }

    public mutating func finish() {
        if !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { _ = consume(pending) }
        pending = ""
    }

    private mutating func consume(_ line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { failed = true; return nil }
        if type == "message_update", let event = json["assistantMessageEvent"] as? [String: Any],
           event["type"] as? String == "text_delta", let delta = event["delta"] as? String {
            guard text.utf8.count + delta.utf8.count <= maxBytes else { failed = true; return nil }
            text += delta
            return delta
        }
        if type == "tool_execution_start", let name = json["toolName"] as? String { toolCalls.append(name) }
        if type == "message_end", let message = json["message"] as? [String: Any],
           ["error", "aborted"].contains(message["stopReason"] as? String ?? "") { failed = true }
        if type == "agent_end" {
            let messages = json["messages"] as? [[String: Any]] ?? []
            let final = messages.last { $0["role"] as? String == "assistant" }
            completed = final?["stopReason"] as? String == "stop"
            if !completed { failed = true }
            if text.isEmpty, let content = final?["content"] as? [[String: Any]] {
                let finalText = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
                guard finalText.utf8.count <= maxBytes else { failed = true; return nil }
                text = finalText
                return finalText.isEmpty ? nil : finalText
            }
        }
        return nil
    }
}
