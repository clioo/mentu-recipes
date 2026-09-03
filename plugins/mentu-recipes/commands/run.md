---
description: Run a Mentu recipe and report what the record actually says
argument-hint: "[recipe name, plus any --var KEY=value]"
allowed-tools: Read, Glob, Grep, Bash
---

Run this recipe and report the result: $ARGUMENTS

1. Validate first with `mentu-recipes check <name>`. Stop and report if it fails.
2. Run it: `mentu-recipes run <name>` with any variables the user gave.
3. Read the record, following the `reading-run-records` skill. Do not report success from the summary line alone: open `run.json`, and for any step that did not succeed, read its `stderr` and any `quarantine/` patch.
4. Report, in this order: the outcome, what each step actually changed, anything quarantined, and the path of the run directory. If a step failed, name the smallest next action: fix the recipe, or `mentu-recipes retry-step <run-id> <label>`.
