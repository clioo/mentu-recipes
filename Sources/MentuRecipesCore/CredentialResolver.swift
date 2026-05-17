import Foundation
import Security

public enum CredentialResolver {
    private static let service = "mentu-vault"

    public static func resolveEnv(_ env: [String: String]) -> [String: String] {
        var resolved = env
        for (key, value) in env where value.hasPrefix("${") && value.hasSuffix("}") {
            let ref = String(value.dropFirst(2).dropLast())
            if let secret = resolveSecret(key: ref) {
                resolved[key] = secret
            }
        }
        return resolved
    }

    public static func resolveSecret(key: String, scope: String? = nil) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }
        for candidate in keychainCandidates(for: key) {
            if let value = try? getKeychain(key: candidate, scope: scope), !value.isEmpty {
                return value
            }
            if scope != nil, let value = try? getKeychain(key: candidate, scope: nil), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    public static func keychainCandidates(for envOrKey: String) -> [String] {
        let upper = envOrKey.uppercased()
        var keys: [String] = [envOrKey]
        let aliases: [String: [String]] = [
            "OPENAI_API_KEY": ["openai-api-key"],
            "ANTHROPIC_API_KEY": ["anthropic-api-key"],
            "DEEPSEEK_API_KEY": ["deepseek-api-key"],
            "GOOGLE_API_KEY": ["google-api-key", "gemini-api-key"],
            "GEMINI_API_KEY": ["gemini-api-key", "google-api-key"],
            "MENTU_API_KEY": ["mentu-api-key", "mentu-api-token"]
        ]
        if let mapped = aliases[upper] {
            keys.append(contentsOf: mapped)
        }
        for suffix in ["_API_KEY", "_TOKEN"] where upper.hasSuffix(suffix) {
            let stem = String(upper.dropLast(suffix.count))
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
            keys.append("\(stem)-\(suffix == "_API_KEY" ? "api-key" : "token")")
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    public static func setKeychain(key: String, value: String, scope: String? = nil) throws {
        let svc = serviceName(scope: scope)
        let query = baseQuery(service: svc, account: key)
        let data = Data(value.utf8)
        var update = query
        update[kSecValueData as String] = data

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw RecipeError.failed("Keychain write failed: \(statusMessage(updateStatus))")
        }

        let addStatus = SecItemAdd(update as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw RecipeError.failed("Keychain write failed: \(statusMessage(addStatus))")
        }
    }

    public static func getKeychain(key: String, scope: String? = nil) throws -> String {
        var query = baseQuery(service: serviceName(scope: scope), account: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            throw RecipeError.failed("Key not found: \(key)")
        }
        if status != errSecSuccess {
            throw RecipeError.failed("Keychain read failed: \(statusMessage(status))")
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw RecipeError.failed("Keychain value is not UTF-8: \(key)")
        }
        return value
    }

    public static func deleteKeychain(key: String, scope: String? = nil) throws {
        let status = SecItemDelete(baseQuery(service: serviceName(scope: scope), account: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw RecipeError.failed("Keychain delete failed: \(statusMessage(status))")
        }
    }

    public static func listKeychain(scope: String? = nil) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(scope: scope),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return [] }
        let rows: [[String: Any]]
        if let array = item as? [[String: Any]] {
            rows = array
        } else if let row = item as? [String: Any] {
            rows = [row]
        } else {
            rows = []
        }
        let keys = rows.compactMap { row in
            row[kSecAttrAccount as String] as? String
        }
        return Array(Set(keys)).sorted()
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func statusMessage(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "OSStatus \(status)"
    }

    private static func serviceName(scope: String?) -> String {
        guard let scope, !scope.isEmpty else { return service }
        return "\(service)/\(scope)"
    }
}
