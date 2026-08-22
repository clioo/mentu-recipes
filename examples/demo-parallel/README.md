# demo-parallel

Seven steps in four layers: three producers fan out, two aggregators join them
pairwise, one merge collapses the pair, and a sentinel refuses to close unless
every layer left evidence behind.

Recipe: [`.mentu/recipes/demo-parallel.json`](../../.mentu/recipes/demo-parallel.json)

```sh
swift build
examples/run-demo.sh demo-parallel
```

## The shape

```
layer 0    alpha        beta        gamma        (concurrent, max_parallel: 3)
              \        /    \       /
layer 1        pair-ab       pair-bg            (concurrent)
                    \       /
layer 2              merge                      (alone in its layer)
                       |
layer 3             sentinel                    (proves the whole DAG)
```

Layers are derived, not declared. Each step's level is one more than the deepest
level among its `depends_on`, steps sharing a level run together up to
`max_parallel`, and a level does not start until the one before it has closed.
You describe the edges; the runner works out the schedule.

## The sentinel

The last step writes nothing. Its whole job is to refuse:

```json
{
  "label": "sentinel",
  "backend": "shell",
  "depends_on": ["merge"],
  "prompt": "echo SENTINEL_COMPLETE",
  "completion_keyword": "SENTINEL_COMPLETE",
  "verify": {
    "grep_present": [
      { "file": "examples/.work/dag/merge.txt", "pattern": "alpha", "min": 1,
        "description": "the merge must carry the alpha producer" },
      { "file": "examples/.work/dag/merge.txt", "pattern": "beta", "min": 1,
        "description": "the merge must carry the beta producer" },
      { "file": "examples/.work/dag/merge.txt", "pattern": "gamma", "min": 1,
        "description": "the merge must carry the gamma producer" }
    ],
    "commands": [
      "test -f examples/.work/dag/pair-ab.txt && test -f examples/.work/dag/pair-bg.txt"
    ]
  }
}
```

Both halves are deliberate. The `grep_present` assertions name each producer, so
a merge that quietly lost a branch is reported in the sentinel's own words. The
`commands` assertion is the hard stop: a non-zero exit fails the step, so a
missing intermediate cannot be waved through as bookkeeping.

## What a clean run looks like

```
▶ alpha · shell
▶ beta · shell
▶ gamma · shell
BETA_COMPLETE
ALPHA_COMPLETE
GAMMA_COMPLETE
▶ pair-bg · shell
▶ pair-ab · shell
PAIR_BG_COMPLETE
PAIR_AB_COMPLETE
▶ merge · shell
MERGE_COMPLETE
▶ sentinel · shell
SENTINEL_COMPLETE

✓ demo-parallel · 7 step(s) · ok

artifacts:
examples/.work/dag/alpha.txt
examples/.work/dag/pair-ab.txt
examples/.work/dag/beta.txt
examples/.work/dag/gamma.txt
examples/.work/dag/pair-bg.txt
examples/.work/dag/merge.txt

commits the runner made for declared artifacts:
32cfae1 chore: mentu-recipes step merge (run_20260822025045_B6D1062B)
edb6fa6 demo baseline
```

The producers finish out of declaration order, which is the concurrency working.
One commit, not six, which is the next section.

## Why the concurrent steps do not use `expected_changes`

Every step here writes into `examples/.work/dag/`, but only `merge` declares
`expected_changes`. The concurrent steps declare their boundary a different way:

```json
"verify": {
  "git_clean_outside": ["examples/.work/dag"],
  "grep_present": [
    { "file": "examples/.work/dag/alpha.txt", "pattern": "alpha", "min": 1,
      "description": "alpha must leave its own artifact behind" }
  ]
}
```

This is not a stylistic choice. `expected_changes` does two jobs at once: it
bounds the writes, and it commits the matching files when the step closes. The
commit half is not safe under concurrency. Steps in the same layer share one git
working tree, so if two of them declare boundaries and close at the same moment,
one commits everything and the other finds nothing left to commit.

Written the naive way, with `expected_changes` on all three producers, this
recipe fails, and the run record says so:

```
--- alpha  failed
  warnings: ['git commit did not create a commit', 'Step failed boundary verification']
  git note: git commit did not create a commit | committed: None | unexpected: []
--- beta   success
  git note: None | committed: ec0364bf8eadfcbddcc99cac87a3b8fb140e93a9
--- gamma  failed
  warnings: ['git commit did not create a commit', 'Step failed boundary verification']
```

`beta` committed all three files. `alpha` and `gamma` did the work, wrote their
artifacts, drifted nowhere, and were marked failed for losing a race. Note
`unexpected: []` in both: the boundary itself held. Only the commit collided.

`verify.git_clean_outside` takes the boundary job without the commit job. It
fails the step if anything appears outside the declared paths, commits nothing,
and leaves the artifacts for a later serial step to own. So `merge`, alone in
layer 2, is the step that declares `expected_changes` and commits the layer.

**The rule to carry away:** in a shared workspace, only a step that is alone in
its layer should declare `expected_changes`. Concurrent steps should bound their
writes with `verify.git_clean_outside` and prove their own artifact with
`verify`, and let a later serial step commit.

Running each concurrent branch in its own isolated worktree removes the
constraint entirely. That is what the full Mentu engine does; this runner
executes every step in one shared workspace, and the rule above is how you work
with that honestly. See [Scope](../../README.md#scope) for the full boundary.

## Checking your own DAG before you run it

```sh
mentu-recipes doctor demo-parallel
```

```
# Mentu Recipes Doctor

- Recipe: `demo-parallel`
- Score: 100

No findings.
```

`doctor` scores a recipe out of 100, subtracting 30 per error, 10 per warning
and 2 per informational finding. It will not tell you whether your layers are
correct, but it will tell you which steps write without declaring a boundary,
which non-shell steps have no observable completion signal, which backends do
not exist, and which shell commands look destructive. Run it with `--strict` in
CI to make warnings fail the build.
