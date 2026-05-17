# Overview

Mentu Recipes is a source-available recipe engine for local agent workflows.
It lets you define multi-step runs as files, keep prompts beside your project,
choose a provider per recipe or per step, and store run records locally.

The public runner focuses on:

- recipe discovery
- prompt rendering
- provider-neutral execution
- shell steps
- retries and timeouts
- macOS Keychain backed vault keys
- local run records
- deterministic verification
- optional Mentu API hooks

The runner is useful because recipes are plain files. You can review them,
version them, run them locally, and share them with a team.

## Product Boundary

This repo documents only the public recipe engine. It does not document or ship
Mentu private intelligence, proprietary evaluation logic, private runtime code,
confidential release systems, or internal automation assets.

The local runner works offline. When a Mentu API key is configured, cloud hooks
can add optional run tracking and step evaluation.

## Mental Model

A recipe is a small workflow:

1. Load a recipe JSON file.
2. Render prompt text and variables.
3. Resolve credentials from env or vault.
4. Run each step with its selected backend.
5. Check local completion and optional verification.
6. Write a run record under `.mentu/runs`.
7. Optionally send run events to `api.mentu.ai`.

The engine does not try to hide what it is doing. The files are the interface.
