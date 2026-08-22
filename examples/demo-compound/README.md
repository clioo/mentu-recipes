# demo-compound

Two recipes run at the same time. A third waits for both, joins their output,
and proves it saw both halves. This is the smallest shape where "concurrent" and
"ordered" have to coexist.

Recipes:
[`demo-compound`](../../.mentu/recipes/demo-compound.json) ·
[`demo-leaf-inventory`](../../.mentu/recipes/demo-leaf-inventory.json) ·
[`demo-leaf-metrics`](../../.mentu/recipes/demo-leaf-metrics.json) ·
[`demo-join-report`](../../.mentu/recipes/demo-join-report.json)

```sh
swift build
examples/run-demo.sh demo-compound
```

## The recipe

A `compound` recipe has no steps of its own. It has nodes, and each node names
another recipe:

```json
{
  "name": "demo-compound",
  "type": "compound",
  "max_parallel": 2,
  "steps": [],
  "recipes": [
    { "label": "inventory", "recipe": "demo-leaf-inventory" },
    { "label": "metrics",   "recipe": "demo-leaf-metrics" },
    { "label": "report",    "recipe": "demo-join-report",
      "depends_on": ["inventory", "metrics"] }
  ]
}
```

`inventory` and `metrics` declare no dependencies, so they are in the same layer
and run together up to `max_parallel`. `report` declares both as dependencies,
so it sits in the next layer and cannot begin until both have closed.

The `"steps": []` is not decoration. A recipe document must carry a `steps` key
even when the type puts all the work in `recipes`; leave it out and the recipe
will not load. See the refusal below.

## The join proves it joined

`demo-join-report` does not simply concatenate and hope. It asserts that both
branches are present in what it produced:

```json
{
  "label": "join",
  "backend": "shell",
  "prompt": "cat examples/.work/inventory.txt examples/.work/metrics.txt > examples/.work/report.txt && echo JOIN_COMPLETE",
  "completion_keyword": "JOIN_COMPLETE",
  "expected_changes": ["examples/.work/report.txt"],
  "verify": {
    "grep_present": [
      { "file": "examples/.work/report.txt", "pattern": "inventory:", "min": 1,
        "description": "the joined report must carry the inventory branch" },
      { "file": "examples/.work/report.txt", "pattern": "metrics:", "min": 1,
        "description": "the joined report must carry the metrics branch" }
    ]
  }
}
```

## What a clean run looks like

```
▶ inventory · shell
INVENTORY_COMPLETE
▶ metrics · shell
METRICS_COMPLETE
▶ join · shell
JOIN_COMPLETE

✓ demo-compound · 3 step(s) · ok

artifacts:
examples/.work/inventory.txt
examples/.work/report.txt
examples/.work/metrics.txt

commits the runner made for declared artifacts:
c315f64 chore: mentu-recipes step join (run_20260822025935_B9DA3902)
897ba5a chore: mentu-recipes step metrics (run_20260822025935_420EC598)
bac2b5b chore: mentu-recipes step inventory (run_20260822025935_5C07BC38)
e79f52f demo baseline
```

Each child recipe committed its own declared artifact under its own run id.

## What you get if you leave the contract fields out

### Omit `steps` on a compound recipe

```
$ mentu-recipes check demo-compound
mentu-recipes: Invalid recipe: /.../demo-compound.json: The data couldn't be read because it is missing.
```

Terse, and it does not name the missing key. Add `"steps": []` and it loads.

### Depend on a node that does not exist

Dependencies are resolved against declared node labels before anything runs:

```
$ mentu-recipes check unknown-dep
mentu-recipes: Invalid recipe: recipe node 'report' depends on unknown node 'pricing'
```

The same check runs over step-level `depends_on`, and cycles are rejected the
same way with `Recipe dependency graph contains a cycle`. A DAG that cannot be
ordered never starts.

### Omit `depends_on` on the join

This is the interesting one, because nothing refuses it. Drop `depends_on` from
the `report` node and all three nodes land in the same layer. With
`max_parallel: 2`, whether `join` finds its inputs on disk depends on which two
nodes the scheduler happened to start first. The run may pass. It may fail with
`cat: examples/.work/inventory.txt: No such file or directory`. It will not be
the same answer every time.

Ordering is the one part of the contract the runner cannot infer for you. It
knows the boundary a step claimed and the proof it owes, because you wrote them
down. It knows a step needs another step's output only if you say so.

## Concurrency and the write boundary

`inventory` and `metrics` run concurrently, and each declares a distinct file in
`expected_changes`, so they never contend. That is the pattern to copy.

Concurrent steps that declare an **overlapping** boundary do contend, because
they share one git working tree and each one commits when it closes. The loser
of that race finds nothing left to commit and reports failure even though its
work succeeded. [demo-parallel](../demo-parallel/README.md) covers the shape
that avoids this.
