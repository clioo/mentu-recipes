---
description: Turn the task you describe into a Mentu recipe, validate it, and offer to run it
argument-hint: "[what the work should do]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

Write a Mentu recipe for this task: $ARGUMENTS

Follow the `writing-recipes` skill. Steps:

1. Check the workspace. If `.mentu/recipes` does not exist, run `mentu-recipes setup --no-run` to create it. If the directory is not a git repository, say so, because the runner commits what a step declares.
2. Split the task into the fewest steps that each have one job. For every step decide, in this order: which paths it may write (`expected_changes`), how it signals completion (`completion_keyword`), what must be true afterwards (`verify`), and only then the prompt.
3. Choose a backend per step. Use `shell` for deterministic work. Use `claude` or `codex` for work that needs a model, and say which one you picked and why.
4. Write the file to `.mentu/recipes/<name>.json`.
5. Validate it and fix what comes back:

```sh
mentu-recipes check <name>
mentu-recipes doctor <name>
```

6. Show the user the recipe and the doctor findings. Tell them the exact command to run it, and do not run it yourself unless they ask.
