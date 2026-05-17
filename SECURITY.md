# Security Policy

## Supported Scope

Mentu Recipes is the public local runner for file-based agent workflows. The
supported security scope is:

- recipe loading from `.mentu/recipes` and `~/.mentu/recipes`
- prompt loading from `.mentu/prompts` and `~/.mentu/prompts`
- provider credential lookup from environment variables and vault keys
- workspace-confined step directories
- shell steps that are explicit in recipe files
- local run records under `.mentu/runs`
- optional calls to `api.mentu.ai`

Mentu private intelligence, proprietary evaluation logic, private runtime code,
and confidential release systems are not part of this repository.

## Reporting

Report security issues privately to `security@mentu.ai`.

Please include:

- affected version or commit
- operating system
- recipe file or minimal reproduction
- impact and expected behavior

Do not include live API keys, tokens, or unrelated private data in the report.

## Handling Secrets

Never commit provider API keys. Use environment variables or:

```sh
printf '%s' "$OPENAI_API_KEY" | mentu-recipes vault set openai-api-key
```

The release scanner checks for common key patterns before publishing. It is a
guardrail, not a substitute for careful review.

## Running Untrusted Recipes

Treat recipes like code. Review a recipe before running it, especially when it
uses the `shell` backend or a custom provider `base_url`.

Use `mentu-recipes check <recipe>` to validate paths and structure before
running a recipe.
