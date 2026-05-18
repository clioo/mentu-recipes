# Security Model

Mentu Recipes is intentionally file-based and inspectable. The main security
rule is simple: treat recipes like code.

## Trust Boundaries

- A recipe can send prompts to configured providers.
- A custom provider `base_url` can receive prompts and provider-specific keys.
- A shell step can execute local commands.
- A recipe with cloud step evaluation enabled can send output tails to
  `api.mentu.ai`.

## Built-In Protections

- Recipe files must be inside approved recipe roots.
- Prompt files must be inside approved prompt roots.
- Prompt symlink escapes are rejected.
- Step directories must stay inside the workspace.
- Verification paths must stay inside the step directory.
- Built-in OpenAI and DeepSeek key names are pinned to official API hosts.
- Shell is explicit only and is never selected automatically.
- Agent CLI environments are allow-listed by backend.
- `expected_changes` can auto-commit intended files and quarantine unrelated
  dirty files into the run directory for review.
- Release scans can include built artifacts as well as source paths.

## Recommended Practice

- Review third-party recipes before running them.
- Use vault keys or environment variables for secrets.
- Do not commit `.env` files or run records.
- Prefer provider-specific env names for custom providers.
- Use deterministic verification for important file checks.
- Use `expected_changes` on writing steps so unrelated edits are quarantined.
- Run `mentu-recipes scan .` before publishing.
