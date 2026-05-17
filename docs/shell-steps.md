# Shell Steps

Shell steps run local commands. Treat recipes with shell steps like code.

## Example

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

## Completion

By default, shell steps complete when the command exits with code `0`.

If `completion_keyword` is set, the keyword must appear in stdout or stderr.

## Working Directory

Use `dir` to run inside a workspace subdirectory:

```json
{
  "label": "test",
  "backend": "shell",
  "dir": "app",
  "prompt": "swift test"
}
```

The `dir` value must be relative and must stay inside the selected workspace.

## Safety Guidance

- Review shell recipes before running them.
- Avoid running untrusted shell recipes.
- Keep destructive commands out of shared examples.
- Use `mentu-recipes check <recipe>` before running a new recipe.
