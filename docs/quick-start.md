# Quick Start

The runner is a single macOS binary. The first run takes under a minute and
needs no credentials.

## 1. Install

```sh
brew install mentu-ai/tap/mentu-recipes-bin
```

Other channels (signed installer package, direct download) are in
[install.md](install.md).

## 2. Run the first-run wizard

Inside any directory you want to use as a workspace:

```sh
mkdir recipe-demo && cd recipe-demo
mentu-recipes setup
```

The wizard does four things, and shows you each one:

1. Lists the backends found on this Mac (`claude`, `codex`, `ollama`, and the
   HTTP providers) and which provider keys are already in the Keychain.
2. Places an example recipe at `.mentu/recipes/hello-justifiable.json`. It has
   two shell steps: `produce` writes `examples/.work/hello.md` inside its
   declared boundary; `prove` checks that the file says what `produce` claimed.
3. Runs the example with the shell backend, so nothing leaves the machine.
4. Prints the path of the run record and the commands to try next.

Flags:

| Flag | Effect |
| --- | --- |
| `--yes` | Skip the prompt and run the example immediately |
| `--no-run` | Detect and scaffold only |
| `--json` | One machine-readable report, no prompts (implies `--yes`) |

## 3. Read the record

```sh
find .mentu/runs -maxdepth 2 -type f
```

Every run leaves `run.json`, `events.jsonl`, `baseline.json`, and one
`stdout`/`stderr` pair per step. The files are plain JSON and text, not
chained, and nothing in this runner verifies them afterwards; see
[run-records.md](run-records.md).

## 4. Use a real backend

If the wizard found `claude` or `codex` on your PATH:

```sh
mentu-recipes run hello-justifiable --backend claude
```

The same recipe, the same boundary, the same record. The only difference is
who does the work. `claude` and `codex` use the CLI's own login; the HTTP
providers need a key in the environment or the vault:

```sh
printf '%s' "$OPENAI_API_KEY" | mentu-recipes vault set OPENAI_API_KEY
```

## 5. Write your own

```sh
mentu-recipes check hello-justifiable    # validate a recipe
mentu-recipes doctor hello-justifiable   # score the contract, list findings
```

`check` validates the file against the schema. `doctor` scores the recipe out
of 100 and lists every finding with a code; `--strict` turns warnings into a
failing exit. Copy the example, change the prompts and the declared paths, and read
[recipe-schema.md](recipe-schema.md) for the full contract.
