import Foundation

public struct HookRunRecord: Codable, Sendable {
    public let event: String
    public let command: String
    public let exitCode: Int32
    public let outputFile: String
    public let errorFile: String

    enum CodingKeys: String, CodingKey {
        case event, command
        case exitCode = "exit_code"
        case outputFile = "output_file"
        case errorFile = "error_file"
    }
}
enum HookRunner {
    static func run(
        event: String,
        commands: [String]?,
        recipe: RecipeDefinition,
        step: RecipeStep?,
        runId: String,
        runDir: URL,
        workspace: URL,
        status: String,
        extraEnv: [String: String] = [:],
        quiet: Bool,
        environment: [String: String]? = nil
    ) async -> [HookRunRecord] {
        guard let commands, !commands.isEmpty else { return [] }
        var records: [HookRunRecord] = []
        for (index, command) in commands.enumerated() {
            let prefix = "hook-\(event)-\(step?.label ?? "run")-\(index + 1)"
            let stdoutFile = "\(prefix).stdout"
            let stderrFile = "\(prefix).stderr"
            var env = environment ?? ProcessInfo.processInfo.environment
            env["MENTU_RECIPES_HOOK_EVENT"] = event
            env["MENTU_RECIPES_RUN_ID"] = runId
            env["MENTU_RECIPES_RECIPE"] = recipe.name
            env["MENTU_RECIPES_STEP"] = step?.label ?? ""
            env["MENTU_RECIPES_BACKEND"] = step?.backend ?? recipe.backend ?? ""
            env["MENTU_RECIPES_MODEL"] = step?.model ?? recipe.model ?? ""
            env["MENTU_RECIPES_WORKSPACE"] = workspace.path
            env["MENTU_RECIPES_STATUS"] = status
            for (key, value) in extraEnv { env[key] = value }
            let result: AdapterResult
            do {
                result = try await ProcessRunner.run(
                    executable: "/bin/sh",
                    arguments: ["-c", command],
                    env: env,
                    workingDirectory: workspace,
                    timeout: 120,
                    maxOutputBytes: 1_000_000,
                    eventSink: { text in
                        if !quiet { FileHandle.standardOutput.write(Data(text.utf8)) }
                    }
                )
            } catch {
                result = AdapterResult(
                    stdout: "",
                    stderr: String(describing: error),
                    exitCode: 127,
                    providerCompleted: false,
                    inputTokens: nil,
                    outputTokens: nil
                )
            }
            try? result.stdout.write(to: runDir.appendingPathComponent(stdoutFile), atomically: true, encoding: .utf8)
            try? result.stderr.write(to: runDir.appendingPathComponent(stderrFile), atomically: true, encoding: .utf8)
            records.append(HookRunRecord(event: event, command: command, exitCode: result.exitCode, outputFile: stdoutFile, errorFile: stderrFile))
        }
        return records
    }
}
