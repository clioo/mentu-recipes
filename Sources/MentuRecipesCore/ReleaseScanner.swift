import Foundation

public struct ReleaseScanFinding: Codable, Sendable {
    public let file: String
    public let reason: String
}

public enum ReleaseScanner {
    private static let localUserPathMarker = ["", "Users", "rashid"].joined(separator: "/")

    private static let protectedTerms: [String] = [
        ["C", "IR"].joined(),
        ["A", "NE"].joined(),
        ["Mentu", "MCP"].joined(),
        ["Spec", "tre"].joined(),
        ["Craw", "lio"].joined(),
        ["Ghi", "dra"].joined(),
        ["Sub", "trace"].joined()
    ]

    private static let confidentialMarker = ["STRICTLY", "CONFIDENTIAL"].joined(separator: " ")

    private static let protectedPathPrefixes: [String] = [
        [".mentu", ["c", "ir"].joined(), ""].joined(separator: "/"),
        ".mentu/state/",
        ".mentu/logs/",
        ".mentu/tmp/",
        ".mentu/training/"
    ]

    public static func scan(root: URL) -> [ReleaseScanFinding] {
        var findings: [ReleaseScanFinding] = []
        let fm = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }

        for case let url as URL in enumerator {
            let relative = relativePath(for: url, rootPath: rootPath)
            for prefix in protectedPathPrefixes where relative.hasPrefix(prefix) {
                findings.append(.init(file: relative, reason: "protected internal path"))
            }
            if shouldSkip(relative) { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let data = try? Data(contentsOf: url),
                  data.count <= 2_000_000,
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }

            if text.contains(localUserPathMarker) {
                findings.append(.init(file: relative, reason: "hardcoded local user path"))
            }
            if text.contains(confidentialMarker) {
                findings.append(.init(file: relative, reason: "confidential marker"))
            }
            if containsLikelySecret(text) {
                findings.append(.init(file: relative, reason: "likely secret token"))
            }
            for term in protectedTerms where containsProtectedTerm(term, in: text) {
                findings.append(.init(file: relative, reason: "protected internal term: \(term)"))
            }
        }
        return findings
    }

    private static func relativePath(for url: URL, rootPath: String) -> String {
        let path = url.resolvingSymlinksInPath().path
        let prefix = rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.path
    }

    private static func shouldSkip(_ relative: String) -> Bool {
        let skips = [
            ".build/",
            ".swiftpm/",
            ".git/",
            ".mentu/runs/",
            ".mentu/cache/"
        ]
        return skips.contains { relative.hasPrefix($0) }
    }

    private static func containsLikelySecret(_ text: String) -> Bool {
        let openAIProjectPrefix = [["s", "k"].joined(), "proj"].joined(separator: "-") + "-"
        let providerKeyPrefix = ["s", "k"].joined() + "-"
        let patterns = [
            NSRegularExpression.escapedPattern(for: openAIProjectPrefix) + #"[A-Za-z0-9_-]{20,}"#,
            NSRegularExpression.escapedPattern(for: providerKeyPrefix) + #"[A-Za-z0-9_-]{20,}"#,
            #"xox[baprs]-[A-Za-z0-9-]{20,}"#,
            #"gh[pousr]_[A-Za-z0-9_]{20,}"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func containsProtectedTerm(_ term: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = "(?i)(^|[^A-Za-z0-9])\(escaped)([^A-Za-z0-9]|$)"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
