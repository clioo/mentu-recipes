# Run Records

Every run writes files under:

```text
.mentu/runs/<run-id>/
```

## `run.json`

The run record includes:

- run ID
- recipe name
- start and end time
- outcome
- cloud mode
- optional cloud run ID
- step records
- run-level hook records
- optional recipe reference
- optional pointers to `events.jsonl`, `state.json`, and `baseline.json`

## Step Output Files

Each step writes:

- `<label>.stdout`
- `<label>.stderr`

The step record points to those file names.

Steps may also include:

- `outcome`: `success`, `warn_bookkeeping`, `failed`, `skipped`, or `cancelled`
- `completion_method`
- token counts reported by a provider
- deterministic verification warnings and errors
- workspace drift attribution
- hook records
- a `git` record with committed paths, commit hash, and quarantined patch files

## `events.jsonl`

New runs also write an append-only event log. It records run start/end, resume,
step queue/start/retry/end, backend selection, verification, hooks, workspace
drift, quarantine, and sanitized errors. Each line is one JSON event. Readers
tolerate a malformed trailing line so interrupted runs remain inspectable.

## `state.json`

The state file powers resume and retry. It stores the original recipe reference,
run variables, backend/model overrides, and each step's current state. Completed
steps marked `success` or `warn_bookkeeping` are skipped during resume.

## `baseline.json`

The baseline file records workspace metadata captured before the run. Step-level
baselines are used internally to subtract pre-existing dirty files from
post-step drift checks.

## Example Shape

```json
{
  "run_id": "run_20260517220000_abcd1234",
  "recipe_name": "shell-smoke",
  "outcome": "ok",
  "cloud_mode": "local-only",
  "steps": [
    {
      "label": "say-hello",
      "backend": "shell",
      "outcome": "success",
      "exit_code": 0,
      "completion_method": "keyword_output",
      "local_complete": true,
      "attempts": 1,
      "output_file": "say-hello.stdout",
      "error_file": "say-hello.stderr"
    }
  ]
}
```

Run records are local project state and are ignored by the public repo.
