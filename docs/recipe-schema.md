# Recipe Schema

A recipe is a JSON object with a name and a list of steps.

## Top-Level Fields

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | string | yes | Recipe name. |
| `description` | string | no | Human-readable description. |
| `backend` | string | no | Default backend for steps. |
| `model` | string | no | Default model for steps. |
| `env` | object | no | Recipe-level environment values. |
| `providers` | object | no | Custom provider definitions. |
| `cloud` | object | no | Optional cloud behavior. |
| `steps` | array | yes | Ordered or dependency-linked steps. |

## Step Fields

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `label` | string | yes | Unique step label. |
| `backend` | string | no | Step backend. Overrides recipe and CLI defaults. |
| `model` | string | no | Step model. Overrides recipe and CLI defaults. |
| `prompt` | string | no | Inline prompt or shell command. |
| `prompt_file` | string | no | Prompt file name from prompt roots. |
| `dir` | string | no | Relative step working directory inside workspace. |
| `env` | object | no | Step-level environment values. |
| `timeout` | integer | no | Timeout in seconds. Default is 1800. |
| `completion_keyword` | string | no | Required output text for local completion. |
| `depends_on` | array | no | Step labels that must run first. |
| `max_retries` | integer | no | Number of retries after the first attempt. |
| `retry_backoff_ms` | integer | no | Wait time between attempts. |
| `max_output_bytes` | integer | no | Output capture limit. Default is 5000000. |
| `reasoning` | string | no | Provider reasoning effort when supported. |
| `max_output_tokens` | integer | no | Provider output token cap when supported. |
| `verify` | object | no | Deterministic verification requirements. |

Each step must provide either `prompt` or `prompt_file`.

## Cloud Fields

```json
{
  "cloud": {
    "enabled": true,
    "evaluate_steps": false
  }
}
```

`enabled` controls cloud run tracking. `evaluate_steps` controls whether step
output tails are sent for cloud evaluation.

## Provider Fields

```json
{
  "providers": {
    "my-provider": {
      "api": "chat_completions",
      "base_url": "https://example.com/v1",
      "api_key_env": "MY_PROVIDER_API_KEY",
      "api_key_vault": "my-provider-api-key",
      "model": "my-model"
    }
  }
}
```

Supported `api` values:

- `responses`
- `chat_completions`
- `cli`
- `shell`

## Minimal Example

```json
{
  "name": "shell-smoke",
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
