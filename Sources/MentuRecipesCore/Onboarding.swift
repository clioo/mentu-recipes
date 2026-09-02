import Foundation

/// The bundled first-run example. Lives in the core so it can be tested the
/// same way any recipe is: decoded, lowered, and run with the shell backend.
public enum Onboarding {
    public static let exampleName = "hello-justifiable"

    public static let exampleRecipeJSON = """
    {
      "name": "hello-justifiable",
      "description": "Two steps: one produces an artifact under a declared path, one proves the artifact says what it claims.",
      "type": "sequence",
      "steps": [
        {
          "label": "produce",
          "backend": "shell",
          "prompt": "mkdir -p examples/.work && printf 'status: ok\\\\nreviewed: yes\\\\n' > examples/.work/hello.md && echo PRODUCE_COMPLETE",
          "completion_keyword": "PRODUCE_COMPLETE",
          "expected_changes": ["examples/.work/hello.md"],
          "timeout": 30
        },
        {
          "label": "prove",
          "backend": "shell",
          "depends_on": ["produce"],
          "prompt": "echo PROVE_COMPLETE",
          "completion_keyword": "PROVE_COMPLETE",
          "verify": {
            "grep_present": [
              {
                "file": "examples/.work/hello.md",
                "pattern": "status: ok",
                "min": 1,
                "description": "hello.md must record the status the produce step claimed to write"
              }
            ]
          },
          "timeout": 30
        }
      ]
    }
    """

    /// Places the example under `.mentu/recipes` unless a file is already there.
    /// Returns the file URL and whether it was written by this call.
    @discardableResult
    public static func scaffoldExample(into workspace: URL) throws -> (url: URL, written: Bool) {
        let paths = RecipePaths(workspace: workspace)
        try FileManager.default.createDirectory(at: paths.projectRecipes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.projectPrompts, withIntermediateDirectories: true)
        let url = paths.projectRecipes.appendingPathComponent("\(exampleName).json")
        if FileManager.default.fileExists(atPath: url.path) { return (url, false) }
        try exampleRecipeJSON.write(to: url, atomically: true, encoding: .utf8)
        return (url, true)
    }
}
