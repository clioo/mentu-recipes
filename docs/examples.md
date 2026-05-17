# Examples

## Shell Smoke

```json
{
  "name": "shell-smoke",
  "description": "Local shell smoke recipe.",
  "steps": [
    {
      "label": "say-hello",
      "backend": "shell",
      "prompt": "echo MENTU_RECIPES_COMPLETE",
      "completion_keyword": "MENTU_RECIPES_COMPLETE",
      "timeout": 10
    }
  ]
}
```

Run:

```sh
mentu-recipes run shell-smoke --no-cloud
```

## OpenAI Smoke

```json
{
  "name": "openai-smoke",
  "backend": "openai",
  "model": "gpt-5.5",
  "steps": [
    {
      "label": "openai-ping",
      "prompt": "Reply with exactly: OPENAI_SMOKE_COMPLETE",
      "completion_keyword": "OPENAI_SMOKE_COMPLETE",
      "timeout": 90
    }
  ]
}
```

Run:

```sh
printf '%s' "$OPENAI_API_KEY" | mentu-recipes vault set openai-api-key
mentu-recipes run openai-smoke --no-cloud
```

## DeepSeek Smoke

```json
{
  "name": "deepseek-smoke",
  "backend": "deepseek",
  "model": "deepseek-chat",
  "steps": [
    {
      "label": "deepseek-ping",
      "prompt": "Reply with exactly: DEEPSEEK_SMOKE_COMPLETE",
      "completion_keyword": "DEEPSEEK_SMOKE_COMPLETE",
      "timeout": 90
    }
  ]
}
```

Run:

```sh
printf '%s' "$DEEPSEEK_API_KEY" | mentu-recipes vault set deepseek-api-key
mentu-recipes run deepseek-smoke --no-cloud
```

## Two-Step Recipe

```json
{
  "name": "two-step",
  "steps": [
    {
      "label": "write-file",
      "backend": "shell",
      "prompt": "printf 'ready\\n' > status.txt"
    },
    {
      "label": "check-file",
      "backend": "shell",
      "depends_on": ["write-file"],
      "prompt": "cat status.txt",
      "completion_keyword": "ready",
      "verify": {
        "grep_present": [
          {
            "file": "status.txt",
            "pattern": "ready",
            "min": 1
          }
        ]
      }
    }
  ]
}
```
