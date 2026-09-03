---
name: writing-recipes
description: Write a Mentu recipe, a JSON file whose steps declare what they may write and what must be true afterwards, then validate it with check and doctor. Use when the user wants repeatable multi-step work on macOS, mentions mentu-recipes or a recipe, or asks to turn a task into something they can rerun and audit.
---

# Writing a Mentu recipe

A recipe is one JSON file under `.mentu/recipes/<name>.json` in the workspace.
Each step says who does the work, how the step signals it finished, which paths
it may change, and what must be true when it is done. The runner enforces the
last two. Write the contract first, the prompt second.

## The smallest recipe that carries a contract

```json
{
  "name": "notes",
  "description": "One step writes a note, one step proves the note says what the first claimed.",
  "type": "sequence",
  "steps": [
    {
      "label": "write",
      "backend": "shell",
      "prompt": "mkdir -p notes && printf 'status: ok\\n' > notes/hello.md && echo WRITE_COMPLETE",
      "completion_keyword": "WRITE_COMPLETE",
      "expected_changes": ["notes/hello.md"],
      "timeout": 60
    },
    {
      "label": "prove",
      "backend": "shell",
      "depends_on": ["write"],
      "prompt": "echo PROVE_COMPLETE",
      "completion_keyword": "PROVE_COMPLETE",
      "verify": {
        "grep_present": [
          { "file": "notes/hello.md", "pattern": "status: ok", "min": 1,
            "description": "the note records the status the write step claimed" }
        ]
      },
      "timeout": 60
    }
  ]
}
```

## The four fields that do the work

- **`expected_changes`** is the write boundary. Declare every path the step may
  change, as a glob or a directory prefix. The runner commits exactly the paths
  that match and quarantines anything else as a patch under the run directory.
  If a step writes only undeclared paths, the step fails.
- **`completion_keyword`** is how the step says it is done. The step counts as
  complete only when the process exits 0 **and** the keyword appears in stdout
  or stderr. A keyword with a non-zero exit is still a failure.
- **`verify`** is checked by the runner after the step, against the files, not
  against the step's word. Kinds: `grep_present`, `grep_absent`, `file_absent`,
  `commands` (run with `/bin/sh` from the step directory), `git_clean_outside`.
  Patterns are literal text, not regular expressions.
- **`depends_on`** orders the work. Steps run in layers: a layer starts only
  after the whole previous layer finishes, so two independent steps in the same
  layer run together and may race on the commit.

## Backends

`shell` for deterministic work, and it is never selected automatically, only by
name. `claude` and `codex` drive the agent CLI already installed on the Mac and
need no API key. `openai`, `openai-chat`, `deepseek` and `ollama` are HTTP
providers; the first three need a key in the environment or the vault. Set
`backend` per step, or once at the top of the recipe as the default.

Prompt variables are `$NAME` or `${NAME}`, filled from `--var NAME=value` and
the recipe `env` block. `{{NAME}}` is not substituted.

## Before you run it

```sh
mentu-recipes check <name>     # schema and references
mentu-recipes doctor <name>    # score out of 100, one line per finding
```

`doctor` names what will be ignored or what is missing: an undeclared boundary,
a step that cannot signal completion, an option the chosen backend does not
support. Fix findings before running. `--strict` makes warnings exit non-zero,
which is what a CI job should use.

## Mistakes to avoid

- A step that writes outside `expected_changes` and nowhere inside it fails,
  it does not merely warn. Declare the real paths.
- Two steps in the same layer that both commit can quarantine each other's
  files. Put them in different layers with `depends_on` when they touch the
  same tree.
- Do not paste secrets into prompts. Store them with
  `printf '%s' "$SECRET" | mentu-recipes vault set <key>` and reference the key.
- Keep `timeout` honest: it is seconds, default 1800.

Full field reference: https://docs.mentu.ai/recipes/schema
