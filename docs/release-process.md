# Release Process

This repo ships a public source package and a signed macOS package.

## Source Gate

Run:

```sh
swift test
swift run mentu-recipes scan .
./scripts/release-validate.sh --source
```

The source gate checks for:

- protected internal terms
- likely secret tokens
- local user paths
- confidential markers
- protected local state paths

## macOS Package Gate

The release script builds, strips, signs, validates, packages, notarizes, and
staples the package:

```sh
./scripts/release-macos.sh
```

The package gate scans:

- compiled binary strings
- compiled binary symbols
- expanded package payload strings
- package payload shape

## Published Artifacts

For `v0.1.0`:

- package: `mentu-recipes-0.1.0-macos-arm64.pkg`
- SHA-256: `a6ab0e0125c90cb1d57361972dc9eeada229a7d9b4c8d3599388c1ada6cee560`
- installer: `curl -fsSL https://get.mentu.ai | sh`

## Public Repo Rule

Only the recipe engine belongs here. Private platform internals and
confidential release materials must stay out of this repo.
