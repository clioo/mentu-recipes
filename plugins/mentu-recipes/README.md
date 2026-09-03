# mentu-recipes plugin for Claude Code

Teaches Claude Code to write work as Mentu recipes and to read the records the
runner leaves.

```
claude plugin marketplace add mentu-ai/mentu-recipes
claude plugin install mentu-recipes@mentu
```

**Skills**, applied when they are relevant:

- `writing-recipes`: the recipe contract, the write boundary, the checks the
  runner performs, and what `check` and `doctor` refuse.
- `reading-run-records`: what a run leaves under `.mentu/runs`, how to find why
  a step failed, and how to resume or retry.

**Commands**, when you want to ask for them:

- `/mentu-recipes:new <task>`: turn a task into a validated recipe.
- `/mentu-recipes:run <name>`: run one and report what the record says.

The plugin drives the `mentu-recipes` command. Install it first:

```
curl -fsSL https://get.mentu.ai | sh
```
