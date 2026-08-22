# hello-justifiable

Two steps. The first produces an artifact at a path it declared in advance. The
second proves the artifact says what the first one claimed. That is the whole
idea, in the smallest form it fits into.

Recipe: [`.mentu/recipes/hello-justifiable.json`](../../.mentu/recipes/hello-justifiable.json)

```sh
swift build
examples/run-demo.sh hello-justifiable
```

## The recipe

```json
{
  "name": "hello-justifiable",
  "type": "sequence",
  "steps": [
    {
      "label": "produce",
      "backend": "shell",
      "prompt": "mkdir -p examples/.work && printf 'status: ok\nreviewed: yes\n' > examples/.work/hello.md && echo PRODUCE_COMPLETE",
      "completion_keyword": "PRODUCE_COMPLETE",
      "expected_changes": ["examples/.work/hello.md"],
      "timeout": 30
    },
    {
      "label": "prove",
      "backend": "shell",
      "depends_on": ["produce"],
      "prompt": "echo PROVE_COMPLETE",
      "completion_keyword": "PROVE_COMPLETE",
      "verify": {
        "grep_present": [
          {
            "file": "examples/.work/hello.md",
            "pattern": "status: ok",
            "min": 1,
            "description": "hello.md must record the status the produce step claimed to write"
          }
        ]
      },
      "timeout": 30
    }
  ]
}
```

Three fields carry the contract. `expected_changes` says where `produce` is
allowed to write. `completion_keyword` says how each step announces it finished.
`verify.grep_present` says what has to be true of the artifact afterwards, and
the `description` is the sentence you will read when it is not.

## What a clean run looks like

```
▶ produce · shell
PRODUCE_COMPLETE
▶ prove · shell
PROVE_COMPLETE

✓ hello-justifiable · 2 step(s) · ok
Run record: .../.mentu/runs/run_20260822024934_1F3BF42F/run.json

artifacts:
examples/.work/hello.md

commits the runner made for declared artifacts:
8ea5fc2 chore: mentu-recipes step produce (run_20260822024934_1F3BF42F)
2c1d023 demo baseline
```

The commit is the point worth pausing on. `produce` declared
`examples/.work/hello.md`, wrote exactly that, and the runner committed it when
the step closed. Nothing else was committed, because nothing else was declared.

## What you get if you leave the contract fields out

### Omit `expected_changes`

The step still runs. `doctor` tells you the boundary is missing before you get
that far:

```
$ mentu-recipes doctor no-boundary

# Mentu Recipes Doctor

- Recipe: `no-boundary`
- Score: 90

| Severity | Code | Location | Recommendation |
| --- | --- | --- | --- |
| warning | missing_expected_changes | steps[0].produce | Declare expected paths or add `verify.git_clean_outside`. |
```

The consequence at runtime is quieter and worse: with no declared boundary the
runner has nothing to commit against, so the artifact is left dirty in the
working tree and the step closes with no record of what it was supposed to
produce. The recipe "passed" without ever saying what success meant.

### Write outside the boundary you declared

Change `produce` to write a second, undeclared file and run it. The run reports
`ok`, but the step is downgraded and the stray file never reaches a commit:

```
--- produce warn_bookkeeping
  warnings: ['Quarantined changes outside expected_changes: examples/.work/UNDECLARED.md']
  expected: ['examples/.work/hello.md'] unexpected: ['examples/.work/UNDECLARED.md']
  quarantine: ['.../run_20260822025107_3612D7B2/quarantine/run_20260822025107_3612D7B2-produce-quarantine.patch']
```

The undeclared change is captured as a patch under the run directory and left
out of the commit. You keep the work; you do not get it silently merged into a
change you did not describe.

### Let the artifact drift from the claim

If `hello.md` no longer contains `status: ok`, the `prove` step surfaces the
`description` you wrote, verbatim:

```
--- prove warn_bookkeeping
  warnings: ['hello.md must record the status the produce step claimed to write']
```

This is a warning, not a failure, and the run still ends `ok`. That is a
deliberate line: `grep_present` is bookkeeping, so a drifting claim is recorded
without halting a long pipeline. When a claim must be load-bearing, assert it in
`verify.commands` instead, where a non-zero exit fails the step:

```json
"verify": {
  "commands": ["grep -q 'status: ok' examples/.work/hello.md"]
}
```

## Where to look afterwards

`.mentu/runs/<run-id>/run.json` holds the whole record: per-step outcome,
warnings, the `git` block with `expected_paths`, `unexpected_paths` and
`committed_hash`, and the paths of any quarantine patches. `mentu-recipes report
<run-id>` renders it as markdown, JSON or CSV.
