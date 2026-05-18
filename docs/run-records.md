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

## Step Output Files

Each step writes:

- `<label>.stdout`
- `<label>.stderr`

The step record points to those file names.

Steps may also include:

- `completion_method`
- token counts reported by a provider
- hook records
- a `git` record with committed paths, commit hash, and quarantined patch files

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
