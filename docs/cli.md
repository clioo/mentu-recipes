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
| `--no-cloud` | Disable Mentu API hooks for this run. |
| `--var KEY=VALUE` | Add a prompt and env variable. Can be repeated. |
| `--quiet` | Reduce step streaming output. |

## `adapters`

```sh
mentu-recipes adapters
```

Prints backend name, execution kind, availability, and auto-detect behavior.

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
mentu-recipes scan [path]
```

Runs the public release scanner against a path.
