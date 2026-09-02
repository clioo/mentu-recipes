import Foundation
import MentuRecipesCore

/// First-run wizard. Four moments, each one something the person can see:
///   1. what is on this Mac (backends on PATH, credentials in the Keychain);
///   2. a bundled example recipe placed in the workspace;
///   3. that example run with the shell backend, no credentials needed;
///   4. the run record on disk, and the two commands to use next.
/// `--yes` skips the prompts; `--json` prints one machine-readable report and
/// makes no interactive decisions; `--no-run` stops after scaffolding.
enum Setup {
    static let exampleName = Onboarding.exampleName


    struct Report: Encodable {
        struct Backend: Encodable {
            let name: String
            let kind: String
            let available: Bool
        }
        let workspace: String
        let backends: [Backend]
        let keychainKeys: [String]
        let exampleRecipe: String
        let exampleWritten: Bool
        let ran: Bool
        let outcome: String?
        let runRecord: String?
        let next: [String]
    }

    static func run(_ args: [String]) async throws {
        let json = args.contains("--json")
        let yes = args.contains("--yes") || json
        let noRun = args.contains("--no-run")
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let env = ProcessInfo.processInfo.environment

        // 1. What is on this Mac.
        let backends = AdapterRegistry.allAdapters().map {
            Report.Backend(name: $0.name, kind: $0.executionKind, available: $0.isAvailable(env: env))
        }
        let keys = CredentialResolver.listKeychain()

        if !json {
            print("Mentu Recipes \(MentuRecipesVersion.string) · first run")
            print("")
            print("Workspace  \(workspace.path)")
            print("")
            print("Backends on this Mac")
            for b in backends {
                print("  \(b.available ? "✓" : "·") \(b.name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(b.available ? "available" : "not found")  (\(b.kind))")
            }
            if keys.isEmpty {
                print("")
                print("Keychain   no provider keys stored; add one later with `mentu-recipes vault set <name>`")
            } else {
                print("")
                print("Keychain   \(keys.joined(separator: ", "))")
            }
        }

        // 2. Place the example recipe.
        let (exampleURL, wrote) = try Onboarding.scaffoldExample(into: workspace)
        if !json {
            print("")
            print("Example    \(exampleURL.path)\(wrote ? "" : "  (already present)")")
            print("           Two shell steps. The first writes examples/.work/hello.md inside its declared boundary;")
            print("           the second proves the file says what the first claimed. No credentials needed.")
        }

        // 3. Run it, unless told not to.
        var ran = false
        var outcome: String?
        var recordPath: String?
        if !noRun {
            var proceed = yes
            if !yes {
                print("")
                print("Run it now? [Y/n] ", terminator: "")
                let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "y"
                proceed = answer.isEmpty || answer == "y" || answer == "yes"
            }
            if proceed {
                if !json { print("") }
                let runner = RecipeRunner(options: RunOptions(workspace: workspace, quiet: json))
                let record = try await runner.run(exampleName)
                ran = true
                outcome = record.outcome
                recordPath = workspace.appendingPathComponent(".mentu/runs/\(record.runId)/run.json").path
                if !json {
                    print("")
                    print("\(record.outcome == "ok" ? "✓" : "✗") \(record.recipeName) · \(record.steps.count) step(s) · \(record.outcome)")
                    print("Record     \(recordPath ?? "")")
                }
            }
        }

        // 4. What to do next.
        let agentBackend = backends.first { $0.available && $0.kind == "agent-cli" }?.name
        var next = ["mentu-recipes run \(exampleName)"]
        if let agentBackend {
            next.append("mentu-recipes run \(exampleName) --backend \(agentBackend)")
        }
        next.append("mentu-recipes doctor \(exampleName)")
        if json {
            let report = Report(
                workspace: workspace.path, backends: backends, keychainKeys: keys,
                exampleRecipe: exampleURL.path, exampleWritten: wrote, ran: ran,
                outcome: outcome, runRecord: recordPath, next: next
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(data: try encoder.encode(report), encoding: .utf8) ?? "{}")
        } else {
            print("")
            print("Next")
            for n in next { print("  \(n)") }
            print("")
            print("Docs       https://docs.mentu.ai/quick-start")
        }
    }
}
