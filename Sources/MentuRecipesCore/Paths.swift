import Foundation

public struct RecipePaths: Sendable {
    public let workspace: URL
    public let home: URL

    public init(workspace: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.workspace = workspace
        self.home = home
    }

    public var projectRecipes: URL { workspace.appendingPathComponent(".mentu/recipes") }
    public var projectPrompts: URL { workspace.appendingPathComponent(".mentu/prompts") }
    public var projectRuns: URL { workspace.appendingPathComponent(".mentu/runs") }
    public var userRecipes: URL { home.appendingPathComponent(".mentu/recipes") }
    public var userPrompts: URL { home.appendingPathComponent(".mentu/prompts") }

    public func resolveRecipe(_ nameOrPath: String) -> URL? {
        let direct = expand(nameOrPath)
        if FileManager.default.fileExists(atPath: direct.path),
           Self.isDescendant(direct, of: projectRecipes) || Self.isDescendant(direct, of: userRecipes) {
            return direct
        }

        let filename = nameOrPath.hasSuffix(".json") ? nameOrPath : "\(nameOrPath).json"
        for root in [projectRecipes, userRecipes] {
            let candidate = root.appendingPathComponent(filename)
            guard Self.isDescendant(candidate, of: root) else { continue }
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func resolvePrompt(_ path: String) -> URL? {
        guard !path.hasPrefix("/"), !path.hasPrefix("~") else { return nil }
        for root in [projectPrompts, userPrompts] {
            let candidate = root.appendingPathComponent(path)
            guard Self.isDescendant(candidate, of: root) else { continue }
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func expand(_ value: String) -> URL {
        if value == "~" {
            return home
        }
        if value.hasPrefix("~/") {
            return home.appendingPathComponent(String(value.dropFirst(2)))
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return workspace.appendingPathComponent(value)
    }

    public static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}
