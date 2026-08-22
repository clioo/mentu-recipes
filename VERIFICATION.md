# Release verification

Every release binary is built by GitHub Actions from the tagged source and
published with a build provenance attestation. Nothing is built on a
maintainer laptop. This page shows the exact commands a stranger can run to
verify a release, together with the real transcript from the `v0.2.1`
release, executed on 2026-08-22 against the public assets with no local
state.

## What the attestation proves

- The binary was produced by the `release.yml` workflow in this repository,
  at the tag it claims, on GitHub-hosted runners.
- The SHA-256 of the asset you downloaded is the SHA-256 the workflow
  attested at build time.
- The signature chains to GitHub's Sigstore instance; forging it would
  require compromising that infrastructure, not this repository.

It does not prove the source is bug-free. It proves the artifact is the
faithful product of the visible source at the visible tag.

## Verify it yourself

Requires `curl`, `shasum`, and the [GitHub CLI](https://cli.github.com) (`gh`).

```sh
curl -sLO https://github.com/mentu-ai/mentu-recipes/releases/download/v0.2.1/mentu-recipes-macos-arm64
curl -sLO https://github.com/mentu-ai/mentu-recipes/releases/download/v0.2.1/checksums.txt
shasum -a 256 -c checksums.txt --ignore-missing
gh attestation verify mentu-recipes-macos-arm64 --repo mentu-ai/mentu-recipes
```

On Intel, substitute `mentu-recipes-macos-x86_64` in both the download and
the verify command.

## Transcript, v0.2.1, 2026-08-22

Checksum:

```text
$ shasum -a 256 -c checksums.txt --ignore-missing
mentu-recipes-macos-arm64: OK
```

Attestation (`--format json`, summarized fields):

```text
attestations found: 1
source repository:  https://github.com/mentu-ai/mentu-recipes
build signer:       .github/workflows/release.yml@refs/tags/v0.2.1
subject sha256:     02f9b1f051c7a399a5dca7c8f940e1a59680a066b07afcf2b1ecb1b3bd924b24
exit code:          0
```

Published checksums for the release:

```text
02f9b1f051c7a399a5dca7c8f940e1a59680a066b07afcf2b1ecb1b3bd924b24  mentu-recipes-macos-arm64
057f5d5a59a5c3319fb740651121bbb255252d727347ab4d84896d4b4e562be8  mentu-recipes-macos-x86_64
```

Smoke test:

```text
$ ./mentu-recipes-macos-arm64
Mentu Recipes
```

Prior release `v0.2.0` was verified with the identical procedure on the same date (arm64 sha `1c3d0cf8c291ee43528d26ea3e7cc3fd5c08658ef2853f0ae306b99968f8fbba`, attestation signer at `refs/tags/v0.2.0`, exit 0).

## Install via Homebrew

```sh
brew install mentu-ai/tap/mentu-recipes-bin
```

The formula pins the same SHA-256 values listed above, so Homebrew refuses
any asset that does not match the attested build.
