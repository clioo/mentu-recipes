# Prompts And Variables

Prompts can be inline or stored as files.

## Inline Prompt

```json
{
  "label": "summarize",
  "backend": "openai",
  "prompt": "Summarize the current project."
}
```

## Prompt File

```json
{
  "label": "summarize",
  "backend": "openai",
  "prompt_file": "summarize.md"
}
```

The file is resolved from:

1. `<workspace>/.mentu/prompts`
2. `~/.mentu/prompts`

## Variables

Pass variables at runtime:

```sh
mentu-recipes run summarize --var TOPIC=release --var AUDIENCE=developers
```

Use variables in prompts and environment values:

```text
Write a release note for {{TOPIC}}.
Audience: {{AUDIENCE}}
```

Variables are simple text replacement. Keep secrets in vault keys or process
environment variables, not in prompt files.
