# Cloud Hooks

Mentu Recipes works offline. Cloud hooks are optional and activate when a Mentu
API key is available.

## Configure A Key

```sh
printf '%s' "$MENTU_API_KEY" | mentu-recipes vault set mentu-api-key
```

Or set:

```sh
export MENTU_API_KEY="..."
```

## Disable Cloud For A Run

```sh
mentu-recipes run my-recipe --no-cloud
```

## Recipe Cloud Config

```json
{
  "cloud": {
    "enabled": true,
    "evaluate_steps": false
  }
}
```

`enabled` controls run start and end calls. `evaluate_steps` controls whether
step output tails are sent for cloud evaluation.

## Local-Only Behavior

If cloud hooks are unavailable, local execution continues. The run record marks
cloud mode as `local-only` or `unavailable`.
