# Credentials And Vault

Credentials can come from:

1. explicit recipe or step `env`
2. process environment variables
3. macOS Keychain vault keys

## Common Keys

| Provider | Env | Vault key |
| --- | --- | --- |
| OpenAI | `OPENAI_API_KEY` | `openai-api-key` |
| Anthropic | `ANTHROPIC_API_KEY` | `anthropic-api-key` |
| DeepSeek | `DEEPSEEK_API_KEY` | `deepseek-api-key` |
| Google or Gemini | `GOOGLE_API_KEY`, `GEMINI_API_KEY` | `google-api-key`, `gemini-api-key` |
| Mentu API | `MENTU_API_KEY` | `mentu-api-key`, `mentu-api-token` |

## Store A Key

```sh
printf '%s' "$OPENAI_API_KEY" | mentu-recipes vault set openai-api-key
```

## Read A Key

```sh
mentu-recipes vault get openai-api-key
```

## List Keys

```sh
mentu-recipes vault list
```

## Delete A Key

```sh
mentu-recipes vault delete openai-api-key
```

## Indirect Env Resolution

Recipe env values can reference vault keys:

```json
{
  "env": {
    "OPENAI_API_KEY": "${openai-api-key}"
  }
}
```

Do not commit real keys in recipe files. Use env variables or vault keys.
