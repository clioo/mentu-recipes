import Foundation
import MentuRecipesCore

enum CLI {
    static func main() async -> Int32 {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            help()
            return 0
        }
        args.removeFirst()

        do {
            switch command {
            case "init":
                try initWorkspace()
            case "check":
                try check(args)
            case "run":
                try await run(args)
            case "adapters":
                adapters()
            case "vault":
                try vault(args)
            case "scan":
                try scan(args)
            case "--help", "-h", "help":
                help()
            default:
                fputs("Unknown command: \(command)\n", stderr)
                help()
                return 2
            }
            return 0
        } catch {
            fputs("mentu-recipes: \(error)\n", stderr)
            return 1
        }
    }

    static func initWorkspace() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let recipes = cwd.appendingPathComponent(".mentu/recipes")
        let prompts = cwd.appendingPathComponent(".mentu/prompts")
        try FileManager.default.createDirectory(at: recipes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)
        print("Initialized .mentu/recipes and .mentu/prompts")
    }

    static func check(_ args: [String]) throws {
        guard let name = args.first else { throw RecipeError.failed("Usage: mentu-recipes check <recipe-or-path>") }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let store = RecipeStore(paths: RecipePaths(workspace: cwd))
        let (recipe, url) = try store.load(name)
        print("✓ \(recipe.name) · \(recipe.steps.count) step(s) · \(url.path)")
    }

    static func run(_ args: [String]) async throws {
        guard let name = args.first else { throw RecipeError.failed("Usage: mentu-recipes run <recipe-or-path>") }
        let parsed = parseOptions(Array(args.dropFirst()))
        let workspace = URL(fileURLWithPath: parsed["workspace"] ?? FileManager.default.currentDirectoryPath)
        let vars = parseVars(parsed["vars"] ?? "")
        let runner = RecipeRunner(options: RunOptions(
            workspace: workspace,
            backend: parsed["backend"],
            model: parsed["model"],
            vars: vars,
            cloudEnabled: parsed["no-cloud"] != "true",
            quiet: parsed["quiet"] == "true"
        ))
        let record = try await runner.run(name)
        let ok = record.outcome == "ok"
        print("\n\(ok ? "✓" : "✗") \(record.recipeName) · \(record.steps.count) step(s) · \(record.outcome)")
        print("Run record: \(workspace.appendingPathComponent(".mentu/runs/\(record.runId)/run.json").path)")
        if !ok { throw RecipeError.failed("Recipe failed") }
    }

    static func adapters() {
        let env = ProcessInfo.processInfo.environment
        for adapter in AdapterRegistry.allAdapters() {
            let available = adapter.isAvailable(env: env) ? "available" : "unavailable"
            let auto = adapter.isAutoDetectable ? "auto" : "explicit"
            print("\(adapter.name)\t\(adapter.executionKind)\t\(available)\t\(auto)")
        }
    }

    static func vault(_ args: [String]) throws {
        guard let sub = args.first else { throw RecipeError.failed("Usage: mentu-recipes vault <set|get|list|delete> ...") }
        switch sub {
        case "set":
            guard args.count == 2 else { throw RecipeError.failed("Usage: printf '%s' \"$SECRET\" | mentu-recipes vault set <key>") }
            let value = readStdinSecret()
            guard !value.isEmpty else { throw RecipeError.failed("No secret received on stdin") }
            try CredentialResolver.setKeychain(key: args[1], value: value)
            print("✓ stored \(args[1])")
        case "get":
            guard args.count >= 2 else { throw RecipeError.failed("Usage: mentu-recipes vault get <key>") }
            let value = try CredentialResolver.getKeychain(key: args[1])
            print(value)
        case "list":
            for key in CredentialResolver.listKeychain() { print(key) }
        case "delete":
            guard args.count >= 2 else { throw RecipeError.failed("Usage: mentu-recipes vault delete <key>") }
            try CredentialResolver.deleteKeychain(key: args[1])
            print("✓ deleted \(args[1])")
        default:
            throw RecipeError.failed("Unknown vault command: \(sub)")
        }
    }

    static func scan(_ args: [String]) throws {
        let root = URL(fileURLWithPath: args.first ?? FileManager.default.currentDirectoryPath)
        let findings = ReleaseScanner.scan(root: root)
        if findings.isEmpty {
            print("✓ release scan passed")
            return
        }
        for finding in findings {
            print("✗ \(finding.file): \(finding.reason)")
        }
        throw RecipeError.failed("release scan failed with \(findings.count) finding(s)")
    }

    static func parseOptions(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var vars: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--workspace", "--backend", "--model":
                if i + 1 < args.count {
                    result[String(arg.dropFirst(2))] = args[i + 1]
                    i += 2
                    continue
                }
            case "--var":
                if i + 1 < args.count {
                    vars.append(args[i + 1])
                    i += 2
                    continue
                }
            case "--no-cloud":
                result["no-cloud"] = "true"
            case "--quiet":
                result["quiet"] = "true"
            default:
                break
            }
            i += 1
        }
        if !vars.isEmpty { result["vars"] = vars.joined(separator: "\n") }
        return result
    }

    static func parseVars(_ raw: String) -> [String: String] {
        var vars: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            vars[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return vars
    }

    static func readStdinSecret() -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        var value = String(data: data, encoding: .utf8) ?? ""
        while value.last == "\n" || value.last == "\r" {
            value.removeLast()
        }
        return value
    }

    static func help() {
        print("""
        Mentu Recipes

        Usage:
          mentu-recipes init
          mentu-recipes check <recipe-or-path>
          mentu-recipes run <recipe-or-path> [--workspace PATH] [--backend NAME] [--model MODEL] [--no-cloud] [--var KEY=VALUE]
          mentu-recipes adapters
          mentu-recipes vault <set|get|list|delete> ...
          mentu-recipes scan [path]
        """)
    }
}

exit(await CLI.main())
