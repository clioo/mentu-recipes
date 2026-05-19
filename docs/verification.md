# Deterministic Verification

Verification lets a step assert local file state after it runs. It is designed
for checks that do not require a model.

## Battle Contract

Mentu Recipes treats broken work and stale bookkeeping differently.

Hard failures:

- process failure or missing completion signal
- `file_absent` violation
- `git_clean_outside` violation for files dirtied by the step
- failed verification command

Bookkeeping warnings:

- missing file for `grep_present` or `grep_absent`
- stale grep pattern
- outdated recipe assertion after the work otherwise completed

Warning steps are recorded as `warn_bookkeeping` and unblock downstream steps.
The recipe author can repair the stale check later without losing a completed
long run.

## Grep Present

```json
{
  "verify": {
    "grep_present": [
      {
        "file": "README.md",
        "pattern": "Mentu Recipes",
        "min": 1
      }
    ]
  }
}
```

## Grep Absent

```json
{
  "verify": {
    "grep_absent": [
      {
        "file": "README.md",
        "pattern": "TODO"
      }
    ]
  }
}
```

## File Absent

```json
{
  "verify": {
    "file_absent": [
      {
        "file": ".env"
      }
    ]
  }
}
```

## Git Clean Outside

```json
{
  "verify": {
    "git_clean_outside": [
      "Sources/",
      "Tests/",
      "README.md"
    ]
  }
}
```

Verification paths are relative to the step directory and cannot escape it.

`git_clean_outside` is snapshot-aware. Dirty files that existed before the step
started are subtracted before the allowed-path check runs. Only files dirtied by
the step can fail this check.

## Commands

```json
{
  "verify": {
    "commands": [
      "swift test",
      "swift run mentu-recipes scan ."
    ]
  }
}
```

Verification commands run from the step directory with a 300 second timeout.
