# Mentu Recipes

Mentu Recipes is a source-available runner for file-based agent workflows.
Define recipes in `.mentu/recipes`, keep reusable prompts in `.mentu/prompts`,
and run them locally against OpenAI, Claude, OpenAI-compatible providers,
local model servers, or shell steps.

The local runner is an execution kernel: it handles recipe discovery, prompt
rendering, provider-neutral execution, retries, timeouts, vault/env resolution,
run logs, and deterministic verification.

Mentu Intelligence lives behind `api.mentu.ai`. When configured, it can add
cloud verdicts, trust scoring, completion adjudication, correction learning,
feature gates, and future premium recipe intelligence. Local execution still
works without a Mentu API key.

## Quick Start

```sh
swift build
swift run mentu-recipes check shell-smoke
swift run mentu-recipes run shell-smoke
```

Recipe files are discovered in this order:

1. `<workspace>/.mentu/recipes`
2. `~/.mentu/recipes`
3. direct file path, only when the file is still inside one of those roots

Prompt files are discovered in:

1. `<workspace>/.mentu/prompts`
2. `~/.mentu/prompts`

Prompt paths are always resolved inside those prompt roots. Absolute paths,
`~`, path traversal, and symlink escapes are rejected.

## Example Recipe

```json
{
  "name": "shell-smoke",
  "description": "One local shell step.",
  "steps": [
    {
      "label": "say-hello",
      "backend": "shell",
      "prompt": "echo MENTU_RECIPES_COMPLETE",
      "completion_keyword": "MENTU_RECIPES_COMPLETE"
    }
  ]
}
```

## Commands

```sh
mentu-recipes init
mentu-recipes check <recipe-or-path>
mentu-recipes run <recipe-or-path> [--workspace PATH] [--backend NAME] [--model MODEL] [--no-cloud] [--var KEY=VALUE]
mentu-recipes adapters
printf '%s' "$SECRET" | mentu-recipes vault set <key>
mentu-recipes vault get <key>
mentu-recipes vault list
mentu-recipes scan [path]
```

## Provider Credentials

Credentials are resolved from explicit recipe env, process env, and the
macOS Keychain service used by Mentu vault keys.

Common key names:

- `OPENAI_API_KEY` or vault key `openai-api-key`
- `ANTHROPIC_API_KEY` or vault key `anthropic-api-key`
- `DEEPSEEK_API_KEY` or vault key `deepseek-api-key`
- `MENTU_API_KEY` or vault key `mentu-api-key`

Custom provider `base_url` values are a trust boundary: a recipe can direct
prompts and provider-specific API keys to that host. Built-in OpenAI and
DeepSeek credential names are pinned to their official API hosts; use a
provider-specific env or vault key for third-party providers.

Shell steps are explicit only and run the command you put in the recipe. Treat
recipes with shell steps like code. Step `dir` values are confined to the
workspace; choose the workspace root intentionally with `--workspace`.

## Cloud Mode

Cloud mode is automatic when a Mentu API key is available. Disable it with:

```sh
mentu-recipes run my-recipe --no-cloud
```

Cloud failures do not stop local execution. Runs are marked local-only when
Mentu Intelligence is unavailable. Step output is not sent for cloud evaluation
unless a recipe explicitly sets `"cloud": { "evaluate_steps": true }`.

## Release Check

Before publishing a source or binary artifact:

```sh
swift run mentu-recipes scan .
```

The scanner fails on private paths, likely secrets, confidential markers, and
protected Mentu platform terms that should not be present in the public repo.
