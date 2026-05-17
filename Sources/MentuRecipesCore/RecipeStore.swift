import Foundation

public struct RecipeStore: Sendable {
    public let paths: RecipePaths

    public init(paths: RecipePaths) {
        self.paths = paths
    }

    public func load(_ nameOrPath: String) throws -> (RecipeDefinition, URL) {
        guard let url = paths.resolveRecipe(nameOrPath) else {
            throw RecipeError.recipeNotFound(nameOrPath)
        }
        let data = try Data(contentsOf: url)
        do {
            let recipe = try JSONDecoder().decode(RecipeDefinition.self, from: data)
            try validate(recipe)
            return (recipe, url)
        } catch let error as RecipeError {
            throw error
        } catch {
            throw RecipeError.invalidRecipe("\(url.path): \(error.localizedDescription)")
        }
    }

    public func validate(_ recipe: RecipeDefinition) throws {
        guard !recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeError.invalidRecipe("name is required")
        }
        guard !recipe.steps.isEmpty else {
            throw RecipeError.invalidRecipe("steps must not be empty")
        }

        var labels = Set<String>()
        for step in recipe.steps {
            guard !step.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RecipeError.invalidRecipe("step label is required")
            }
            guard Self.isSafeStepLabel(step.label) else {
                throw RecipeError.invalidRecipe("step label must be 1-128 characters of A-Z, a-z, 0-9, dot, underscore, or dash, and must start with a letter or number: \(step.label)")
            }
            guard labels.insert(step.label).inserted else {
                throw RecipeError.duplicateStep(step.label)
            }
            if step.prompt == nil && step.promptFile == nil {
                throw RecipeError.missingPrompt(label: step.label)
            }
        }

        let known = Set(labels)
        for step in recipe.steps {
            for dep in step.dependsOn ?? [] where !known.contains(dep) {
                throw RecipeError.invalidRecipe("step '\(step.label)' depends on unknown step '\(dep)'")
            }
        }
        _ = try topologicalOrder(recipe.steps)
    }

    public func topologicalOrder(_ steps: [RecipeStep]) throws -> [RecipeStep] {
        let byLabel = Dictionary(uniqueKeysWithValues: steps.map { ($0.label, $0) })
        var temporary = Set<String>()
        var permanent = Set<String>()
        var ordered: [RecipeStep] = []

        func visit(_ label: String) throws {
            if permanent.contains(label) { return }
            if temporary.contains(label) { throw RecipeError.dependencyCycle }
            guard let step = byLabel[label] else { return }

            temporary.insert(label)
            for dep in step.dependsOn ?? [] {
                try visit(dep)
            }
            temporary.remove(label)
            permanent.insert(label)
            ordered.append(step)
        }

        for step in steps {
            try visit(step.label)
        }
        return ordered
    }

    private static func isSafeStepLabel(_ label: String) -> Bool {
        label.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil
    }
}
