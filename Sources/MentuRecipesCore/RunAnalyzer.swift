import CryptoKit
import Foundation

public struct RunAnalysisSummary: Codable, Sendable {
    public let workspace: String
    public let runs: Int
    public let successRate: Double
    public let backendSummary: [BackendRunSummary]
    public let recommendations: [RunRecommendation]

    enum CodingKeys: String, CodingKey {
        case workspace, runs
        case successRate = "success_rate"
        case backendSummary = "backend_summary"
        case recommendations
    }
}

public struct BackendRunSummary: Codable, Sendable {
    public let backend: String
    public let steps: Int
    public let successRate: Double
    public let medianDurationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case backend, steps
        case successRate = "success_rate"
        case medianDurationSeconds = "median_duration_seconds"
    }
}

public struct RunRecommendation: Codable, Sendable {
    public let code: String
    public let message: String
    public let targetHash: String?

    enum CodingKeys: String, CodingKey {
        case code, message
        case targetHash = "target_hash"
    }
}

public enum RunAnalyzer {
    public static func analyze(workspace: URL, redacted: Bool = true) -> RunAnalysisSummary {
        let runsDir = workspace.appendingPathComponent(".mentu/runs")
        let records = loadRecords(from: runsDir)
        let total = records.count
        let successCount = records.filter { $0.outcome == "ok" }.count
        let backendGroups = Dictionary(grouping: records.flatMap(\.steps), by: \.backend)
        let summaries = backendGroups.keys.sorted().map { backend in
            let steps = backendGroups[backend] ?? []
            let ok = steps.filter { $0.localComplete }.count
            let durations = steps.map(\.durationSeconds).sorted()
            return BackendRunSummary(
                backend: backend,
                steps: steps.count,
                successRate: steps.isEmpty ? 0 : Double(ok) / Double(steps.count),
                medianDurationSeconds: median(durations)
            )
        }
        let recommendations = recommendations(records: records, redacted: redacted)
        return RunAnalysisSummary(
            workspace: redacted ? "redacted" : workspace.path,
            runs: total,
            successRate: total == 0 ? 0 : Double(successCount) / Double(total),
            backendSummary: summaries,
            recommendations: recommendations
        )
    }

    public static func render(_ summary: RunAnalysisSummary, format: ReportFormat) throws -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(data: try encoder.encode(summary), encoding: .utf8) ?? "{}"
        case .csv:
            var lines = ["backend,steps,success_rate,median_duration_seconds"]
            for backend in summary.backendSummary {
                lines.append("\(backend.backend),\(backend.steps),\(backend.successRate),\(backend.medianDurationSeconds)")
            }
            return lines.joined(separator: "\n") + "\n"
        case .markdown:
            var lines = [
                "# Mentu Recipes Run Analysis",
                "",
                "- Workspace: `\(summary.workspace)`",
                "- Runs: \(summary.runs)",
                "- Success rate: \(String(format: "%.2f", summary.successRate))",
                "",
                "| Backend | Steps | Success Rate | Median Duration |",
                "| --- | ---: | ---: | ---: |"
            ]
            for backend in summary.backendSummary {
                lines.append("| \(backend.backend) | \(backend.steps) | \(String(format: "%.2f", backend.successRate)) | \(backend.medianDurationSeconds)s |")
            }
            if !summary.recommendations.isEmpty {
                lines += ["", "## Recommendations", ""]
                for recommendation in summary.recommendations {
                    lines.append("- `\(recommendation.code)`: \(recommendation.message)")
                }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    public static func exportJSONL(_ summary: RunAnalysisSummary, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(summary) + Data("\n".utf8)
        try data.write(to: url)
    }

    private static func loadRecords(from runsDir: URL) -> [RecipeRunRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return urls.compactMap { url in
            let runJSON = url.appendingPathComponent("run.json")
            guard let data = try? Data(contentsOf: runJSON) else { return nil }
            return try? JSONDecoder().decode(RecipeRunRecord.self, from: data)
        }
    }

    private static func recommendations(records: [RecipeRunRecord], redacted: Bool) -> [RunRecommendation] {
        var output: [RunRecommendation] = []
        let failedSteps = Dictionary(grouping: records.flatMap(\.steps).filter { !$0.localComplete }, by: \.label)
        for (label, steps) in failedSteps where steps.count >= 2 {
            output.append(RunRecommendation(
                code: "repeated_step_failure",
                message: "A step failed \(steps.count) times; add stronger verification, split the task, or adjust timeout.",
                targetHash: redacted ? hash(label) : label
            ))
        }
        let missingCompletion = records.flatMap(\.steps).filter { $0.completionMethod == "provider_complete" && ($0.verification?.warnings.isEmpty ?? true) }
        if !missingCompletion.isEmpty {
            output.append(RunRecommendation(
                code: "add_verification",
                message: "\(missingCompletion.count) provider-complete step(s) would benefit from deterministic `verify` checks.",
                targetHash: nil
            ))
        }
        let quarantineCount = records.flatMap(\.steps).reduce(0) { $0 + ($1.git?.quarantineFiles.count ?? 0) }
        if quarantineCount > 0 {
            output.append(RunRecommendation(
                code: "tighten_expected_changes",
                message: "\(quarantineCount) quarantined patch(es) found; narrow or correct `expected_changes`.",
                targetHash: nil
            ))
        }
        return output
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values[values.count / 2]
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
