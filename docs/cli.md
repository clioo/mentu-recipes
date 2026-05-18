# CLI Reference

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

## `report`

```sh
mentu-recipes report <run-id> [--format markdown|json|csv] [--workspace PATH]
```

Loads `.mentu/runs/<run-id>/run.json` and renders a human-readable report,
machine-readable JSON, or CSV.

## `adapters`

```sh
mentu-recipes adapters
```

Prints backend name, execution kind, stream format, system-context handling,
availability, and auto-detect behavior. Availability checks are non-blocking and
only inspect environment variables or local executables; vault-only credentials
can still be used by explicitly selecting a backend.

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
