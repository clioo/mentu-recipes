# Recipe Concepts

## Workspace

A workspace is the directory where a recipe runs. By default it is the current
directory. You can override it:

```sh
mentu-recipes run my-recipe --workspace /path/to/project
```

Recipe step directories must stay inside the workspace.

## Recipes

Recipes are JSON files stored in:

1. `<workspace>/.mentu/recipes`
2. `~/.mentu/recipes`

A direct file path is allowed only when the file is still inside one of those
roots.

## Prompts

Prompts can be inline or loaded from prompt files. Prompt files are stored in:

1. `<workspace>/.mentu/prompts`
2. `~/.mentu/prompts`

Prompt paths cannot be absolute, cannot use `~`, cannot traverse upward, and
cannot escape through symlinks.

## Backends

A backend executes a step. The public runner includes:

- `shell`
- `openai`
- `openai-chat`
- `deepseek`
- `ollama`
- `claude`
- custom provider entries through `providers`

Backends can be set at recipe level, step level, or via CLI option.

## Completion

A step is locally complete when:

- the process exits successfully, and
- the backend completion policy is satisfied, and
- the optional `completion_keyword` is present when configured

Shell steps complete by exit code unless a keyword is configured.

## Run Records

Every run writes a record under:

```text
.mentu/runs/<run-id>/run.json
```

Each step also writes stdout and stderr files.
