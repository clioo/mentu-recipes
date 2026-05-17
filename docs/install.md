# Install

## macOS Package

Install the signed and notarized macOS package:

```sh
curl -fsSL https://get.mentu.ai | sh
```

The installer:

1. Fetches the release manifest from `api.mentu.ai`.
2. Downloads the package for your platform.
3. Verifies the SHA-256 checksum.
4. Verifies the package with Gatekeeper.
5. Installs `mentu-recipes` to `/usr/local/bin/mentu-recipes`.

## Build From Source

```sh
git clone https://github.com/mentu-ai/mentu-recipes.git
cd mentu-recipes
swift build
swift test
```

Run from source:

```sh
swift run mentu-recipes adapters
```

## Requirements

- macOS on Apple Silicon for the packaged release
- Swift toolchain for source builds
- `curl` for the installer
- `plutil`, `shasum`, and `spctl` for installer verification

## Verify The Installed Binary

```sh
mentu-recipes adapters
mentu-recipes init
mentu-recipes check shell-smoke
```
