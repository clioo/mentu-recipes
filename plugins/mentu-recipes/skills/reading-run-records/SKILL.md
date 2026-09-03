---
name: reading-run-records
description: Read what a Mentu run left on disk under .mentu/runs to find out what a step actually did, why it failed, and what was quarantined, then resume or retry the right step. Use when a mentu-recipes run failed or warned, when asked what happened in a run, or when checking that a step did what it claimed.
---

# Reading a Mentu run record

Every run writes one directory: `.mentu/runs/run_<timestamp>_<id>/`. Read it
instead of trusting the summary line. Start with the outcome, then the step
that broke, then the evidence.

## What is in the directory

| File | What it holds |
| --- | --- |
| `run.json` | The summary: recipe, outcome, per-step results, cloud mode. |
| `events.jsonl` | Every event in order, one JSON object per line. Appended on resume. |
| `state.json` | Per-step state and attempt counts. This is what `resume` reads. |
| `baseline.json` | The tree as it was before the run. |
| `<label>.stdout`, `<label>.stderr` | Raw output per step. |
| `hook-<event>-<label>-<n>.stdout` | Hook output, when the recipe has hooks. |
| `quarantine/` | Patches for files a step changed but did not declare. |

## Reading it

```sh
mentu-recipes report <run-id>                  # markdown, json or csv
find .mentu/runs -maxdepth 2 -type f           # everything the run wrote
```

Then, in order:

1. **Outcome.** `ok` means every step completed and every check passed.
   `failed` means a step did not. `warn_bookkeeping` means the work happened
   but the runner could not record it the usual way, for example outside a git
   worktree or when nothing matched the declared boundary.
2. **The failing step.** Read its `stderr` first, then `stdout`. A step that
   printed its completion keyword but exited non-zero is still a failure, and
   the exit code is in the record.
3. **Verification.** A failed `verify` names the file and the pattern it wanted.
   Check the file itself before changing the recipe: often the step wrote
   something slightly different from what it claimed.
4. **Quarantine.** If `quarantine/` has patches, the step wrote paths it never
   declared. Either add those paths to `expected_changes` because they are real
   output, or fix the step because it is writing where it should not.

## Getting the run moving again

```sh
mentu-recipes resume <run-id>                     # rerun what did not succeed
mentu-recipes retry-step <run-id> <step-label>    # rerun one step
```

`resume` skips steps recorded as `success` or `warn_bookkeeping` and reruns the
rest, with the variables the original run used. `retry-step` reruns one named
step and bumps its attempt count. Both accept `--backend`, `--model`,
`--max-parallel` and `--quiet`.

## Across many runs

```sh
mentu-recipes analyze-runs                        # patterns over the run history
```

It reports three recommendations: tighten a boundary that keeps quarantining
files, raise a timeout that keeps expiring, and split a step that keeps failing.
Step labels appear as hashes.

Full layout: https://docs.mentu.ai/reference/cli
