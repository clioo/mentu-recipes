# Deterministic Verification

Verification lets a step assert local file state after it runs. It is designed
for checks that do not require a model.

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
