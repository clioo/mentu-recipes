import Foundation

public struct PromptRenderer: Sendable {
    public let paths: RecipePaths

    public init(paths: RecipePaths) {
        self.paths = paths
    }

    public func prompt(for step: RecipeStep, vars: [String: String]) throws -> String {
        let raw: String
        if let inline = step.prompt {
            raw = inline
        } else if let promptFile = step.promptFile, let url = paths.resolvePrompt(promptFile) {
            raw = try String(contentsOf: url, encoding: .utf8)
        } else {
            throw RecipeError.missingPrompt(label: step.label)
        }
        return Self.render(raw, vars: vars)
    }

    public static func render(_ text: String, vars: [String: String]) -> String {
        var rendered = text
        for (key, value) in vars.sorted(by: { $0.key.count == $1.key.count ? $0.key < $1.key : $0.key.count > $1.key.count }) {
            rendered = rendered.replacingOccurrences(of: "${\(key)}", with: value)
            rendered = rendered.replacingOccurrences(of: "$\(key)", with: value)
        }
        return rendered
    }
}
