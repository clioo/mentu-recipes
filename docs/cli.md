# CLI Reference

## `list`

```sh
mentu-recipes list [--json]
```

The recipes in `.mentu/recipes`, one per line with the step count and the
description. `--json` prints name, path, steps and description per recipe. With
an empty workspace it says so and names `setup`.

Every subcommand accepts `--help` and prints its usage without doing anything
else.

## `setup`

```sh
mentu-recipes setup [--yes] [--json] [--no-run]
```

Before it offers to run anything, `setup` says what the run will do to this
directory: a step that writes inside its declared boundary is committed as
`chore: mentu-recipes step <label>`, and anything outside the boundary is kept
as a patch under `.mentu/runs/` instead. Outside a git repository it says that
nothing can be committed.

First-run wizard. Detects backends on PATH and provider keys in the Keychain,
scaffolds `hello-justifiable` into `.mentu/recipes` (never overwriting), runs it
with the shell backend, and prints the run record path. `--yes` skips the
prompt, `--no-run` stops after scaffolding, `--json` prints one report and
implies `--yes`.

## `init`

```sh
mentu-recipes init
```

Creates:

- `.mentu/recipes`
- `.mentu/prompts`

## `check`

```sh
mentu-recipes check <recipe-or-path>
```

Loads and validates a recipe.

## `plan`

```sh
mentu-recipes plan <recipe-or-path> [options]
```

Returns a JSON review digest for resolved execution inputs without running hooks,
tools, or models. It does resolve credentials from the vault for the selected
backends, so it can touch the login Keychain. Use the same workspace, backend, model, variables, parallel
limit, and cloud options when executing. See [Admitted Execution](admitted-execution.md)
for the guarantees, recovery behavior, and limitations.

## `run`

```sh
mentu-recipes run <recipe-or-path> [options]
```

Options:

| Option | Description |
| --- | --- |
| `--workspace PATH` | Run in a specific workspace. |
| `--backend NAME` | Set a default backend for steps without one. |
| `--model MODEL` | Set a default model for steps without one. |
| `--cloud` | Enable Mentu API run hooks for this run. |
| `--max-parallel N` | Limit parallel step or child-recipe execution. |
| `--var KEY=VALUE` | Add a prompt and env variable. Can be repeated. |
| `--quiet` | Reduce step streaming output. |
| `--plan-digest SHA256` | Opt into content-bound execution admission; requires a request key. |
| `--request-key KEY` | Deduplicate one operation; requires an approved plan digest. |

## `resume`

```sh
mentu-recipes resume <run-id> [--workspace PATH]
```

Loads `.mentu/runs/<run-id>/state.json`, skips steps already marked
`success` or `warn_bookkeeping`, and reruns incomplete branches. Resume appends
new events to the existing `events.jsonl`.

Admitted runs require `--plan-digest`, a new `--request-key` for the recovery
intent, and the original plan options including `--var` substitutions.

## `retry-step`

```sh
mentu-recipes retry-step <run-id> <step-label> [--workspace PATH]
```

Marks one step as pending and resumes the run. Completed dependencies remain
complete.

In admitted mode, dependent step evidence is invalidated and rechecked. The
original digest and plan options are required, as for `resume`.

## `report`

```sh
mentu-recipes report <run-id> [--format markdown|json|csv] [--workspace PATH]
```

Loads `.mentu/runs/<run-id>/run.json` and renders a human-readable report,
machine-readable JSON, or CSV.

## `adapters`

```sh
mentu-recipes adapters [--json|--explain NAME]
```

Prints backend name, execution kind, stream format, system-context handling,
availability, and auto-detect behavior. Availability checks are non-blocking and
only inspect environment variables or local executables; vault-only credentials
can still be used by explicitly selecting a backend.

`--json` prints machine-readable adapter capabilities. `--explain NAME` prints
why a backend behaves the way it does: local/cloud boundary, network and
credential needs, tool support, and completion policy.

## `doctor`

```sh
mentu-recipes doctor <recipe-or-path> [--format markdown|json|csv] [--strict]
```

Runs deterministic local recipe intelligence. It checks observable completion,
expected-change coverage, backend compatibility, custom provider credential
boundaries, dangerous shell patterns, and portability hints. Strict mode exits
non-zero on warnings as well as errors.

## `analyze-runs`

```sh
mentu-recipes analyze-runs [--workspace PATH] [--format markdown|json|csv] [--export-jsonl PATH]
```

Summarizes local run records without reading prompt or output contents. The
default output is redacted and aggregates success rates, backend behavior,
durations, quarantine frequency, and recommendations.

## `vault`

```sh
mentu-recipes vault set <key>
mentu-recipes vault get <key>
mentu-recipes vault list
mentu-recipes vault delete <key>
```

Use stdin when setting a secret:

```sh
printf '%s' "$SECRET" | mentu-recipes vault set my-key
```

## `scan`

```sh
mentu-recipes scan [path] [--artifact PATH]
```

Runs the public release scanner against a source path and optional built
artifacts.
