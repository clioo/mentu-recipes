# Examples

Three recipes you can run right now. They use the `shell` backend, so they need
no API key, no credential and no network. Every transcript on these pages was
produced by running the recipe in this repository.

| Example | Shape | Teaches |
| --- | --- | --- |
| [hello-justifiable](hello-justifiable/README.md) | 2 steps, sequential | A step declares where it will write, and a later step proves the artifact says what was claimed. |
| [demo-compound](demo-compound/README.md) | 3 child recipes, DAG | Two recipes run concurrently, a third joins them and cannot start until both have closed. |
| [demo-parallel](demo-parallel/README.md) | 7 steps, 4 layers | Fan out, join, merge, and a sentinel that refuses to close unless every layer left evidence. |

## Running them

```sh
swift build
examples/run-demo.sh hello-justifiable
examples/run-demo.sh demo-compound
examples/run-demo.sh demo-parallel
```

`run-demo.sh` copies the recipes into a scratch git repository under `$TMPDIR`
and runs them there. That matters: a step that declares `expected_changes` gets
its artifacts committed by the runner when the step closes, and you probably do
not want those commits landing in your clone of this repository.

To run one against a workspace of your own instead:

```sh
mentu-recipes run hello-justifiable --workspace /path/to/your/project
```

The recipe has to be resolvable from that workspace. Recipes are looked up in
`<workspace>/.mentu/recipes` and then `~/.mentu/recipes`, by name, and paths
outside those two roots are rejected. Copy the JSON into one of them first.

## The contract these examples are built on

A step makes claims before it runs, and the runner checks them after:

- **`expected_changes`** is the write boundary. Files created inside it are
  staged and committed when the step closes. Files created outside it are
  written to a quarantine patch under the run directory and left uncommitted.
- **`verify`** is the proof. `grep_present` and `grep_absent` assert what a file
  must and must not say. `commands` runs shell assertions. `file_absent` asserts
  a path does not exist. `git_clean_outside` declares a write boundary without
  committing anything.
- **`completion_keyword`** is the completion signal. The step is complete only
  if the keyword appears in its output, whatever the exit code says.

Not every check carries the same weight, and it is worth knowing which is which
before you rely on one:

| Check | On failure |
| --- | --- |
| `completion_keyword` absent from output | step fails |
| `verify.commands` non-zero exit | step fails |
| `verify.file_absent` matches | step fails |
| `verify.git_clean_outside` violated | step fails |
| `verify.grep_present` / `grep_absent` unmet | step is marked `warn_bookkeeping`, run continues |
| write outside `expected_changes` | change is quarantined, step is marked `warn_bookkeeping` |

So `grep_present` tells you loudly that a claim did not hold, and records it in
the run, but it will not stop the run. If you need a hard stop, put the same
assertion in `verify.commands`.

## Cleaning up

`run-demo.sh` leaves its scratch workspace in `$TMPDIR` so you can read the run
records. Delete it when you are done. If you ran a demo directly against this
repository instead of through the script, reset the commits the runner made:

```sh
git reset --hard origin/main
rm -rf examples/.work .mentu/runs
```
