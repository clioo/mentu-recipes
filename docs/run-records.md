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

## Step Output Files

Each step writes:

- `<label>.stdout`
- `<label>.stderr`

The step record points to those file names.

## Example Shape

```json
{
  "runId": "run_20260517220000_abcd1234",
  "recipeName": "shell-smoke",
  "outcome": "ok",
  "cloudMode": "local-only",
  "steps": [
    {
      "label": "say-hello",
      "backend": "shell",
      "exitCode": 0,
      "localComplete": true,
      "attempts": 1,
      "outputFile": "say-hello.stdout",
      "errorFile": "say-hello.stderr"
    }
  ]
}
```

Run records are local project state and are ignored by the public repo.
