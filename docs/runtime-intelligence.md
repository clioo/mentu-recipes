# Runtime Intelligence

Mentu Recipes runtime intelligence is local-first and deterministic by default.
It turns recipe runs into useful evidence without requiring a cloud service or a
specific LLM provider.

## Evidence Files

Every new run writes:

- `run.json`: summary record
- `events.jsonl`: append-only lifecycle events
- `state.json`: resumable step state
- `baseline.json`: pre-run workspace metadata

These files live under `.mentu/runs/<run-id>/`.

## Step Outcomes

Steps can end as:

- `success`: work completed
- `warn_bookkeeping`: work completed, but a recipe assertion appears stale
- `failed`: work did not complete or dirtied files outside scope
- `skipped`: dependency or resume logic skipped the step
- `cancelled`: reserved for interrupted runs

`success` and `warn_bookkeeping` unblock downstream steps.

## Doctor

```sh
mentu-recipes doctor <recipe> [--strict]
```

Doctor checks recipe quality before a run:

- observable completion
- deterministic verification coverage
- expected-change coverage
- adapter capability compatibility
- provider credential boundaries
- dangerous shell patterns

It is local-only and rules-based.

## Analyze Runs

```sh
mentu-recipes analyze-runs
```

Analyzer summarizes local run records. It does not read prompt contents or full
step output. The default report is redacted and focuses on aggregate behavior:
success rate, backend behavior, duration, quarantine frequency, and improvement
recommendations.

## Resume

```sh
mentu-recipes resume <run-id>
mentu-recipes retry-step <run-id> <step-label>
```

Resume loads `state.json`, skips completed steps, and reruns incomplete branches.
Retry-step marks one step pending and continues the run with its original recipe
variables.

## Adapter Capabilities

```sh
mentu-recipes adapters --json
mentu-recipes adapters --explain claude
```

Adapter capability metadata lets recipes stay provider-neutral. The runner can
reason about execution kind, network needs, credential needs, tool support, and
completion policy without hard-coding one model provider.
