# Contributing

Thanks for helping improve Mentu Recipes.

## Before Opening A Change

Run:

```sh
swift test
swift run mentu-recipes scan .
```

For release changes, also run:

```sh
./scripts/release-validate.sh --source
```

## Contribution Guidelines

- Keep the repo focused on the public recipe runner.
- Do not add private Mentu platform internals or confidential release material.
- Do not commit provider keys, local vault data, personal paths, or generated run logs.
- Keep recipes and prompts reviewable as plain files.
- Prefer small changes with tests for behavior changes.
- Use plain documentation text. Do not use em dashes in public docs.

## Code Style

Follow the existing Swift style. Keep abstractions small and provider-neutral.
Shell behavior should stay explicit and easy to inspect.

## License

By contributing, you agree that your contribution is provided under the license
in this repository.
