import Foundation

public enum ReportFormat: String {
    case markdown
    case json
    case csv
}

public enum RunReporter {
    public static func load(runId: String, workspace: URL) throws -> RecipeRunRecord {
        let path = workspace.appendingPathComponent(".mentu/runs/\(runId)/run.json")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(RecipeRunRecord.self, from: data)
    }

    public static func render(_ record: RecipeRunRecord, format: ReportFormat) throws -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        case .csv:
            var lines = ["run_id,recipe,step,backend,model,exit_code,complete,duration_seconds,attempts,committed_hash,quarantine_count"]
            for step in record.steps {
                lines.append([
                    record.runId,
                    record.recipeName,
                    step.label,
                    step.backend,
                    step.model ?? "",
                    String(step.exitCode),
                    String(step.localComplete),
                    String(step.durationSeconds),
                    String(step.attempts),
                    step.git?.committedHash ?? "",
                    String(step.git?.quarantineFiles.count ?? 0)
                ].map(csvEscape).joined(separator: ","))
            }
            return lines.joined(separator: "\n") + "\n"
        case .markdown:
            var lines: [String] = [
                "# Mentu Recipes Run",
                "",
                "- Run: `\(record.runId)`",
                "- Recipe: `\(record.recipeName)`",
                "- Outcome: `\(record.outcome)`",
                "- Started: \(record.startedAt)",
                "- Ended: \(record.endedAt ?? "running")",
                "- Cloud: `\(record.cloudMode)`",
                "",
                "| Step | Backend | Complete | Exit | Duration | Attempts | Commit | Quarantine |",
                "| --- | --- | ---: | ---: | ---: | ---: | --- | ---: |"
            ]
            for step in record.steps {
                let commit = step.git?.committedHash.map { String($0.prefix(12)) } ?? ""
                lines.append("| \(step.label) | \(step.backend) | \(step.localComplete ? "yes" : "no") | \(step.exitCode) | \(step.durationSeconds)s | \(step.attempts) | \(commit) | \(step.git?.quarantineFiles.count ?? 0) |")
            }
            if !record.hooks.isEmpty || record.steps.contains(where: { !($0.hooks ?? []).isEmpty }) {
                lines += ["", "## Hooks", ""]
                for hook in record.hooks {
                    lines.append("- \(hook.event): `\(hook.command)` exit \(hook.exitCode)")
                }
                for step in record.steps {
                    for hook in step.hooks ?? [] {
                        lines.append("- \(step.label) \(hook.event): `\(hook.command)` exit \(hook.exitCode)")
                    }
                }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    private static func csvEscape(_ raw: String) -> String {
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") {
            return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return raw
    }
}
