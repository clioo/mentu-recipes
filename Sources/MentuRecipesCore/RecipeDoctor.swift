import Foundation

public struct RecipeQualityFinding: Codable, Sendable {
    public let severity: String
    public let code: String
    public let location: String
    public let message: String
    public let recommendation: String
}

public struct RecipeQualityReport: Codable, Sendable {
    public let recipeName: String
    public let score: Int
    public let findings: [RecipeQualityFinding]

    enum CodingKeys: String, CodingKey {
        case recipeName = "recipe_name"
        case score, findings
    }
}

public enum RecipeDoctor {
    public static func inspect(_ nameOrPath: String, store: RecipeStore, backendOverride: String? = nil) -> RecipeQualityReport {
        do {
            let (recipe, _) = try store.load(nameOrPath)
            return inspect(recipe, backendOverride: backendOverride)
        } catch {
            return RecipeQualityReport(
                recipeName: nameOrPath,
                score: 0,
                findings: [
                    finding(
                        severity: "error",
                        code: "invalid_recipe",
                        location: "recipe",
                        message: String(describing: error),
                        recommendation: "Fix the recipe so it loads with `mentu-recipes check`."
                    )
                ]
            )
        }
    }

    public static func inspect(_ recipe: RecipeDefinition, backendOverride: String? = nil) -> RecipeQualityReport {
        var findings: [RecipeQualityFinding] = []
        let type = recipe.type ?? .sequence
        if type == .sequence || type == .formula {
            var labels = Set<String>()
            for (index, step) in recipe.steps.enumerated() {
                let location = "steps[\(index)].\(step.label)"
                if !labels.insert(step.label).inserted {
                    findings.append(finding(severity: "error", code: "duplicate_step", location: location, message: "Step label is duplicated.", recommendation: "Use unique step labels."))
                }
                let backendName = step.backend ?? backendOverride ?? recipe.backend
                let adapter = backendName.flatMap { AdapterRegistry.adapter(named: $0, providers: recipe.providers ?? [:]) }
                if let backendName, adapter == nil {
                    findings.append(finding(severity: "error", code: "unknown_backend", location: location, message: "Backend `\(backendName)` is not registered.", recommendation: "Choose a built-in backend or define a custom provider."))
                }
                let caps = adapter?.capabilities
                if adapter?.executionKind != "shell",
                   step.completionKeyword == nil,
                   step.verify == nil {
                    findings.append(finding(severity: "warning", code: "missing_completion_signal", location: location, message: "Non-shell step has no completion keyword or deterministic verification.", recommendation: "Add `completion_keyword` or `verify` so completion is observable."))
                }
                if likelyWrites(step), step.expectedChanges == nil, step.verify?.gitCleanOutside == nil {
                    findings.append(finding(severity: "warning", code: "missing_expected_changes", location: location, message: "Step appears to write files but does not declare a write boundary.", recommendation: "Declare expected paths or add `verify.git_clean_outside`."))
                }
                if adapter?.executionKind == "shell", let prompt = step.prompt, looksDestructive(prompt) {
                    findings.append(finding(severity: "error", code: "destructive_shell", location: location, message: "Shell command contains a destructive pattern.", recommendation: "Review the command and scope it to the workspace before running."))
                }
                if let caps {
                    if step.allowedTools != nil, !caps.supportsToolAllowList {
                        findings.append(finding(severity: "warning", code: "unsupported_allowed_tools", location: location, message: "Selected backend does not support tool allow-lists.", recommendation: "Use an agent CLI backend or remove `allowed_tools`."))
                    }
                    if step.disallowedTools != nil, !caps.supportsToolDenyList {
                        findings.append(finding(severity: "warning", code: "unsupported_disallowed_tools", location: location, message: "Selected backend does not support tool deny-lists.", recommendation: "Use an agent CLI backend or remove `disallowed_tools`."))
                    }
                    if step.thinking != nil, !caps.supportsThinking {
                        findings.append(finding(severity: "warning", code: "unsupported_thinking", location: location, message: "Selected backend does not support `thinking`.", recommendation: "Use a backend that supports thinking options or remove the field."))
                    }
                }
                if step.timeout == nil, adapter?.executionKind != "shell" {
                    findings.append(finding(severity: "info", code: "default_timeout", location: location, message: "Step uses the default timeout.", recommendation: "Set `timeout` for long-running provider steps."))
                }
            }
        }
        findings += providerFindings(recipe)
        let score = max(0, 100 - findings.reduce(0) { partial, finding in
            partial + penalty(for: finding.severity)
        })
        return RecipeQualityReport(recipeName: recipe.name, score: score, findings: findings)
    }

    public static func render(_ report: RecipeQualityReport, format: ReportFormat) throws -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(data: try encoder.encode(report), encoding: .utf8) ?? "{}"
        case .csv:
            var lines = ["recipe,score,severity,code,location,message,recommendation"]
            for finding in report.findings {
                lines.append([
                    report.recipeName,
                    String(report.score),
                    finding.severity,
                    finding.code,
                    finding.location,
                    finding.message,
                    finding.recommendation
                ].map(csvEscape).joined(separator: ","))
            }
            return lines.joined(separator: "\n") + "\n"
        case .markdown:
            var lines = [
                "# Mentu Recipes Doctor",
                "",
                "- Recipe: `\(report.recipeName)`",
                "- Score: \(report.score)",
                ""
            ]
            if report.findings.isEmpty {
                lines.append("No findings.")
            } else {
                lines += ["| Severity | Code | Location | Recommendation |", "| --- | --- | --- | --- |"]
                for finding in report.findings {
                    lines.append("| \(finding.severity) | \(finding.code) | \(finding.location) | \(finding.recommendation) |")
                }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    private static func providerFindings(_ recipe: RecipeDefinition) -> [RecipeQualityFinding] {
        (recipe.providers ?? [:]).compactMap { name, config in
            let env = config.apiKeyEnv?.uppercased()
            let vault = config.apiKeyVault?.lowercased()
            guard env == "OPENAI_API_KEY" || env == "DEEPSEEK_API_KEY" || vault == "openai-api-key" || vault == "deepseek-api-key" else {
                return nil
            }
            return finding(
                severity: "error",
                code: "generic_provider_credential",
                location: "providers.\(name)",
                message: "Custom provider uses a built-in provider credential name.",
                recommendation: "Use a provider-specific `api_key_env` or `api_key_vault`."
            )
        }
    }

    private static func likelyWrites(_ step: RecipeStep) -> Bool {
        let text = [step.prompt, step.promptFile].compactMap { $0 }.joined(separator: " ").lowercased()
        let signals = [">", "touch ", "mv ", "cp ", "rm ", "sed -i", "write", "edit", "modify", "create", "fix", "update"]
        return signals.contains { text.contains($0) }
    }

    private static func looksDestructive(_ command: String) -> Bool {
        let text = command.lowercased()
        let patterns = ["rm -rf /", "sudo rm -rf", "mkfs", "diskutil erase", "dd if=", ":(){", "chmod -r 777 /"]
        return patterns.contains { text.contains($0) }
    }

    private static func penalty(for severity: String) -> Int {
        switch severity {
        case "error": return 30
        case "warning": return 10
        default: return 2
        }
    }

    private static func finding(severity: String, code: String, location: String, message: String, recommendation: String) -> RecipeQualityFinding {
        RecipeQualityFinding(severity: severity, code: code, location: location, message: message, recommendation: recommendation)
    }

    private static func csvEscape(_ raw: String) -> String {
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") {
            return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return raw
    }
}
