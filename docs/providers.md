# Providers

Mentu Recipes uses backends to execute steps. A backend can be selected at the
recipe level, step level, or CLI level.

## Built-In Backends

| Backend | Type | Notes |
| --- | --- | --- |
| `shell` | local process | Explicit only. Runs the prompt as a shell command. |
| `openai` | HTTP LLM | Uses the OpenAI Responses API. |
| `openai-chat` | HTTP LLM | Uses OpenAI chat completions. |
| `deepseek` | HTTP LLM | Uses DeepSeek chat completions. |
| `ollama` | local HTTP LLM | Uses `http://localhost:11434/v1`. |
| `claude` | CLI agent | Uses the local Claude CLI when available. |

## Selection Order

Backend selection follows this order:

1. Step `backend`
2. CLI `--backend`
3. Recipe `backend`
4. Auto-detect from available non-shell providers

Shell is never auto-detected.

## OpenAI Responses

```json
{
  "name": "openai-smoke",
  "backend": "openai",
  "model": "gpt-5.5",
  "steps": [
    {
      "label": "ping",
      "prompt": "Reply with exactly: OK",
      "completion_keyword": "OK",
      "reasoning": "medium",
      "max_output_tokens": 32
    }
  ]
}
```

OpenAI model aliases accepted by the runner include:

- `codex-5-5` maps to `gpt-5.5`
- `gpt-5-5` maps to `gpt-5.5`
- `gpt-5-4-mini` maps to `gpt-5.4-mini`
- `codex-5-3` maps to `gpt-5.3-codex`

## Custom Provider

Use `providers` when a service has an OpenAI-compatible API but should use its
own key.

```json
{
  "name": "custom-chat",
  "providers": {
    "acme": {
      "api": "chat_completions",
      "base_url": "https://api.acme.example/v1",
      "api_key_env": "ACME_API_KEY",
      "api_key_vault": "acme-api-key",
      "model": "acme-large"
    }
  },
  "steps": [
    {
      "label": "ask",
      "backend": "acme",
      "prompt": "Reply with exactly: ACME_OK",
      "completion_keyword": "ACME_OK"
    }
  ]
}
```

Provider `base_url` is a trust boundary. Built-in OpenAI and DeepSeek key names
are pinned to their official hosts. For third-party hosts, define a
provider-specific env or vault key.
