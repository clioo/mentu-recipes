---
id: BUILD-Mentu-Recipes-Intelligence-v1
type: build-sequence
version: "1.0"
created: 2026-05-19
updated: 2026-05-19
domain: recipe-runtime
classification: PUBLIC-SAFE BUILD PLAN
grounded_in:
  - Public runner audit: Sources/MentuRecipesCore and Sources/mentu-recipes
  - Local run corpus audit: 500+ executed recipes and accumulated run evidence
  - Adapter corpus audit: backend metadata, parser behavior, and provider routing traces
  - Workspace history audit: file-history, quarantine, hook, and run-state patterns
  - Existing release hardening: scanner, provider log sanitizer, credential boundaries
status: "PLANNED - runtime intelligence layer for a provider-neutral recipe runner"
---

# BUILD: Mentu Recipes Intelligence v1

> Goal: turn the accumulated recipe-running wisdom into a clean, public-safe,
> LLM-agnostic intelligence layer for `mentu-recipes`.
>
> Rule: distill patterns from the local corpus; do not copy private corpora,
> private model weights, private prompts, internal datasets, or proprietary
> evaluation logic into this repository.

---

## v1 Delta

The current public runner is already a capable local execution kernel. The next
build should make it the best recipe runner by adding durable run evidence,
workspace-aware safety, recipe quality intelligence, adapter capability
introspection, resumability, and local aggregate learning.

| # | Item | Effort | Source Learning |
|---|------|--------|-----------------|
| 1 | Append-only `events.jsonl` beside `run.json` | 1 day | Run evidence is more useful than final summaries alone. |
| 2 | Workspace baseline and drift detection | 1 day | File-history and quarantine patterns show that provenance matters. |
| 3 | `doctor` command with recipe quality report | 1-2 days | Repeated run failures cluster around missing verification, weak completion, and backend mismatch. |
| 4 | Adapter capability registry | 1 day | Backend choice must be validated against behavior, not just names. |
| 5 | Step state machine plus resume/retry | 2-3 days | Long recipe runs need continuation, not all-or-nothing reruns. |
| 6 | `analyze-runs` local intelligence command | 1-2 days | The run corpus can produce recommendations without exposing private content. |
| 7 | Public/private intelligence extension boundary | 1 day | Private classifiers should plug in through schemas and hooks, not live in the runner. |

---

## Constraints

- Do not ship private training data, local run contents, model checkpoints, or
  internal prompts.
- Do not make a cloud service required for local recipe execution.
- Do not assume a single LLM provider or provider-specific response shape in
  core recipe logic.
- Do not send step output to any remote service unless the recipe explicitly
  opts in.
- Do not auto-run shell steps from untrusted recipes.
- Do not hide backend behavior behind opaque magic. The runner should explain
  why a backend was selected or rejected.
- Do not let intelligence weaken deterministic checks. Intelligence suggests;
  verification decides.

---

## What Already Works

| Capability | Files | Status |
|------------|-------|--------|
| Recipe discovery and validation | `RecipeStore.swift`, `Paths.swift`, `RecipeModels.swift` | DONE |
| Prompt rendering and safe prompt lookup | `PromptRenderer.swift`, `Paths.swift` | DONE |
| Provider-neutral adapter interface | `Adapters.swift` | DONE |
| HTTP providers and local model server support | `HTTPAdapters.swift` | DONE |
| Agent CLI adapters with structured stream parsing | `ShellAdapter.swift`, `CodexCLIAdapter.swift` | DONE |
| Provider log cleanup | `ProviderLogSanitizer.swift` | DONE |
| Shell backend | `ShellAdapter.swift` | DONE |
| Step retries, timeouts, and output limits | `RecipeRunner.swift`, `ProcessRunner.swift` | DONE |
| DAG and parallel execution | `RecipeRunner.swift`, `AsyncSemaphore.swift` | DONE |
| Child recipe nodes | `RecipeRunner.swift`, `RecipeModels.swift` | DONE |
| Hooks around run and step lifecycle | `HookRunner.swift`, `RecipeRunner.swift` | DONE |
| Deterministic verification | `Verification.swift`, `RecipeModels.swift` | DONE |
| Expected-change commit and quarantine | `GitWorkspace.swift` | DONE |
| Run reports | `RunReporter.swift` | DONE |
| Vault/env credential resolution | `CredentialResolver.swift` | DONE |
| Release scanner | `ReleaseScanner.swift` | DONE |

---

## Critical Path

```text
Phase 1: Evidence Spine
  1.1 Add RunEvent schema
  1.2 Add RunEventWriter with atomic append
  1.3 Emit events from RecipeRunner
  1.4 Report from run.json plus events.jsonl

Phase 2: Workspace Baseline
  2.1 Capture pre-run git status and file snapshot metadata
  2.2 Compare pre-step and post-step drift
  2.3 Record provenance in step git records
  2.4 Harden quarantine report shape

Phase 3: Recipe Quality Intelligence
  3.1 Add RecipeDoctor
  3.2 Add `mentu-recipes doctor`
  3.3 Add strict mode for CI
  3.4 Document score rules and examples

Phase 4: Adapter Capability Intelligence
  4.1 Add AdapterCapability
  4.2 Validate recipe fields against adapter support
  4.3 Add adapter explanation output
  4.4 Use capabilities in doctor and run preflight

Phase 5: Resume, Retry, and Replay
  5.1 Add StepState model
  5.2 Persist runnable plan state
  5.3 Add `resume` and `retry-step`
  5.4 Add cancellation-safe process cleanup

Phase 6: Learn From Runs
  6.1 Add RunAnalyzer
  6.2 Add prompt/output redaction by default
  6.3 Add aggregate recommendations
  6.4 Add anonymized export format

Phase 7: Extension Boundary
  7.1 Define local intelligence provider contract
  7.2 Define external verdict event shape
  7.3 Keep private intelligence optional and replaceable
```

---

## Phase 1: Evidence Spine

### 1.1 RunEvent Schema

**Gap**: `run.json` is useful as a final summary, but it loses the temporal
shape of a run: when retries happened, when hooks fired, when verification
failed, when a backend streamed completion, and what changed before failure.

**Build**:

Create `Sources/MentuRecipesCore/RunEvents.swift`.

```swift
public struct RunEvent: Codable, Sendable {
    public let id: String
    public let runId: String
    public let sequence: Int
    public let timestamp: String
    public let kind: RunEventKind
    public let recipeName: String
    public let stepLabel: String?
    public let backend: String?
    public let status: String?
    public let message: String?
    public let data: [String: String]?
}

public enum RunEventKind: String, Codable, Sendable {
    case runStarted = "run_started"
    case runFinished = "run_finished"
    case stepQueued = "step_queued"
    case stepStarted = "step_started"
    case stepRetried = "step_retried"
    case stepFinished = "step_finished"
    case verificationStarted = "verification_started"
    case verificationFinished = "verification_finished"
    case hookStarted = "hook_started"
    case hookFinished = "hook_finished"
    case workspaceDrift = "workspace_drift"
    case quarantineWritten = "quarantine_written"
    case error = "error"
}
```

**Files**:

| File | Action |
|------|--------|
| `RunEvents.swift` | CREATE schema and writer |
| `RecipeRunner.swift` | MODIFY emit lifecycle events |
| `HookRunner.swift` | MODIFY optionally return event payloads |
| `RunReporter.swift` | MODIFY include event summary |
| `Tests/MentuRecipesCoreTests` | ADD event log tests |

### 1.2 Event Writer

Use newline-delimited JSON. Each event append must be crash-tolerant enough for
local runs:

- create parent directory first
- encode one event per line
- append using `FileHandle`
- keep sequence monotonic within one process
- tolerate missing or truncated final line while reading reports

### 1.3 Event Coverage

Emit at minimum:

- run started and finished
- step queued, started, retried, finished
- backend selected
- verification started and finished
- hook started and finished
- expected-change commit result
- quarantine patch written
- sanitized error

### 1.4 Acceptance Tests

- Shell smoke run creates `events.jsonl`.
- Failed step still writes `run_finished` with failed status.
- Retry emits exactly one `step_retried` event per retry.
- Reporter can load `run.json` when `events.jsonl` is absent.
- Reporter ignores a malformed trailing event line.

---

## Phase 2: Workspace Baseline

### 2.1 Baseline Before Run

**Gap**: `expected_changes` can commit intended files and quarantine unrelated
dirty paths, but the runner does not yet separate pre-existing workspace dirt
from changes created by the current recipe.

**Build**:

Create `Sources/MentuRecipesCore/WorkspaceBaseline.swift`.

```swift
public struct WorkspaceBaseline: Codable, Sendable {
    public let capturedAt: String
    public let gitRoot: String?
    public let head: String?
    public let dirtyPaths: [String]
    public let untrackedPaths: [String]
}
```

Capture once before the run and optionally before each step. The baseline
should be metadata only by default, not file contents.

### 2.2 Drift Classification

Classify dirty paths into:

- `preexisting`: present before the recipe
- `created_by_step`: changed after a step
- `expected`: matched by `expected_changes`
- `unexpected`: created by the step but not declared
- `ignored_run_state`: runner-owned files under `.mentu/runs`

### 2.3 Git Record Upgrade

Extend `StepGitRecord`:

```swift
public struct StepGitRecord: Codable, Sendable {
    public let changedPaths: [String]
    public let expectedPaths: [String]
    public let unexpectedPaths: [String]
    public let preexistingPaths: [String]
    public let committedHash: String?
    public let quarantineFiles: [String]
    public let note: String?
}
```

Keep decoding backward compatible by making new fields optional or adding a
custom decoder.

### 2.4 Acceptance Tests

- A file dirty before the run is not attributed to the step.
- A new unexpected file is quarantined.
- A matching expected file is committed.
- Reports distinguish pre-existing dirt from new drift.

---

## Phase 3: Recipe Quality Intelligence

### 3.1 RecipeDoctor

**Gap**: `check` validates shape, but it does not say whether a recipe is good,
portable, safe, resumable, or verifiable.

**Build**:

Create `Sources/MentuRecipesCore/RecipeDoctor.swift`.

```swift
public struct RecipeQualityReport: Codable, Sendable {
    public let recipeName: String
    public let score: Int
    public let findings: [RecipeQualityFinding]
}

public struct RecipeQualityFinding: Codable, Sendable {
    public let severity: String
    public let code: String
    public let location: String
    public let message: String
    public let recommendation: String
}
```

### 3.2 Initial Rules

| Rule | Severity | Rationale |
|------|----------|-----------|
| Step has neither `completion_keyword` nor `verify` for LLM/agent backend | warning | Completion should be observable. |
| Writing step lacks `expected_changes` | warning | Workspace drift cannot be bounded. |
| Shell step contains destructive command patterns | error/warning | Recipes are code; local damage should be visible. |
| Step timeout missing on non-shell backend | info | Long runs should have predictable failure bounds. |
| Backend unknown | error | Run will fail. |
| Backend requires field unsupported by adapter | error | Provider mismatch. |
| DAG cycle | error | Recipe cannot execute. |
| Parallel recipe lacks `max_parallel` and has many nodes | warning | Avoid accidental local saturation. |
| Custom provider uses generic credential env | error | Prevent key leakage to unexpected hosts. |
| Verification command exists without timeout override | info | Default is safe, but visible. |

### 3.3 CLI

Add:

```sh
mentu-recipes doctor <recipe-or-path> [--format markdown|json] [--strict]
```

Strict mode exits non-zero on warnings. Default exits non-zero only on errors.

### 3.4 Acceptance Tests

- Minimal shell smoke scores high.
- LLM step without completion signal emits warning.
- Custom provider with generic key emits error.
- JSON report is stable and sorted.
- Strict mode fails on warning.

---

## Phase 4: Adapter Capability Intelligence

### 4.1 AdapterCapability

**Gap**: Adapters expose name, stream format, completion policy, and system
context handling. That is the right base, but recipe quality and preflight need
more explicit capabilities.

**Build**:

Extend `BackendAdapter` with a backward-compatible capability property.

```swift
public struct AdapterCapability: Codable, Sendable {
    public let supportsTools: Bool
    public let supportsToolAllowList: Bool
    public let supportsToolDenyList: Bool
    public let supportsReasoning: Bool
    public let supportsThinking: Bool
    public let supportsMaxOutputTokens: Bool
    public let reportsTokenUsage: Bool
    public let supportsStructuredCompletion: Bool
    public let canRunOffline: Bool
    public let requiresNetwork: Bool
    public let requiresCredential: Bool
}
```

### 4.2 Preflight Validation

Before a run:

- check selected backend exists
- check unsupported fields and warn or fail
- check required credentials non-blockingly where possible
- explain auto-detection choice
- keep explicit backend selection valid even when vault credentials are used

### 4.3 CLI Output

Upgrade:

```sh
mentu-recipes adapters --json
mentu-recipes adapters --explain codex
```

### 4.4 Acceptance Tests

- Capabilities render for every built-in adapter.
- Doctor catches unsupported field combinations.
- `adapters --json` is machine-readable.
- Vault-only credentials do not block explicit backend selection.

---

## Phase 5: Resume, Retry, and Replay

### 5.1 Step State Machine

**Gap**: The current runner can retry inside one process, but it cannot resume a
partially completed recipe after interruption.

**Build**:

Add persistent step state:

```swift
public enum StepState: String, Codable, Sendable {
    case pending
    case running
    case ok
    case failed
    case skipped
    case cancelled
}
```

Write `state.json` in the run directory. Keep `run.json` as the public summary.

### 5.2 Resume Semantics

Add:

```sh
mentu-recipes resume <run-id> [--workspace PATH]
mentu-recipes retry-step <run-id> <step-label> [--workspace PATH]
```

Resume should:

- load the original recipe reference and variables from the run record
- skip successful steps
- rerun failed, cancelled, skipped, or pending steps when dependencies permit
- append new events rather than rewriting history
- mark resumed attempts in both `run.json` and `events.jsonl`

### 5.3 Replay Mode

Later extension:

```sh
mentu-recipes replay <run-id> --dry-run
```

Replay explains what would run, what would be skipped, and which workspace
baseline conditions no longer match.

### 5.4 Acceptance Tests

- Interrupted two-step recipe resumes from step two.
- Failed dependency keeps downstream step skipped.
- Retry-step refuses unknown labels.
- Resume appends events and preserves old attempt evidence.

---

## Phase 6: Learn From Runs

### 6.1 RunAnalyzer

**Gap**: The local corpus contains the evidence needed to improve recipes, but
the public runner has no command to summarize it.

**Build**:

Create `Sources/MentuRecipesCore/RunAnalyzer.swift`.

Add:

```sh
mentu-recipes analyze-runs [--workspace PATH] [--format markdown|json] [--redacted]
```

Default behavior must be redacted. It should aggregate metadata, not prompt
content or full model output.

### 6.2 Metrics

Aggregate:

- recipes run
- success rate by recipe
- failure rate by step
- backend success rate
- median duration by backend and step
- retry frequency
- verification failure frequency
- quarantine frequency
- missing completion signal frequency
- token usage when available

### 6.3 Recommendations

Produce local recommendations:

- "Add `verify` to steps with repeated false completion."
- "Add `expected_changes` to steps that often dirty the workspace."
- "Increase timeout for step X or split it."
- "Backend Y has high failure rate for this recipe; pin backend Z or add fallback."
- "This recipe is a good candidate for parallel waves."

### 6.4 Anonymized Export

Add:

```sh
mentu-recipes analyze-runs --export-jsonl path/to/redacted.jsonl
```

Export records must use hashes for recipe and step names unless
`--include-names` is explicitly set.

### 6.5 Acceptance Tests

- Analyzer works with current `run.json` files.
- Analyzer works when `events.jsonl` exists.
- Redacted export contains no stdout, stderr, prompts, env values, or absolute
  local paths.
- Recommendations are deterministic for fixed fixture data.

---

## Phase 7: Extension Boundary

### 7.1 Local Intelligence Provider

**Gap**: Private classifiers and judgment systems should be usable by Mentu
users who have them, but the public runner must remain clean and portable.

**Build**:

Define a provider-neutral interface:

```swift
public protocol RecipeIntelligenceProvider: Sendable {
    func inspect(recipe: RecipeDefinition) async throws -> [RecipeQualityFinding]
    func evaluate(event: RunEvent) async throws -> [RunEvent]
    func recommend(summary: RunAnalysisSummary) async throws -> [RunRecommendation]
}
```

The public implementation can be deterministic only. Private or cloud-backed
implementations can plug in through separate packages or API hooks.

### 7.2 Event Contract

All private or external intelligence must communicate through public event
types and report types:

- `RunEvent`
- `RecipeQualityReport`
- `RunAnalysisSummary`
- `RunRecommendation`

No private object model should leak into recipe files.

### 7.3 Cloud Boundary

Cloud intelligence remains optional:

- local run works offline
- recipe opts into cloud explicitly
- step output is never uploaded unless enabled by recipe config
- local analyzer redacts by default

### 7.4 Acceptance Tests

- Public runner builds without private packages.
- Cloud disabled path has no network dependency.
- External intelligence failure does not corrupt run records.
- Release scanner passes source and binary artifacts.

---

## File Summary

### New Files

| File | Purpose |
|------|---------|
| `Sources/MentuRecipesCore/RunEvents.swift` | Append-only run evidence schema and writer. |
| `Sources/MentuRecipesCore/WorkspaceBaseline.swift` | Baseline and drift classification. |
| `Sources/MentuRecipesCore/RecipeDoctor.swift` | Deterministic recipe quality report. |
| `Sources/MentuRecipesCore/RunStateStore.swift` | Persistent step state for resume/retry. |
| `Sources/MentuRecipesCore/RunAnalyzer.swift` | Local aggregate learning from run records. |
| `Sources/MentuRecipesCore/RecipeIntelligence.swift` | Public extension contracts. |
| `docs/runtime-intelligence.md` | User-facing explanation of doctor, analyze, resume, and evidence logs. |

### Modified Files

| File | Change |
|------|--------|
| `Sources/MentuRecipesCore/RecipeRunner.swift` | Emit events, write state, capture baselines, support resume path. |
| `Sources/MentuRecipesCore/RecipeModels.swift` | Add optional run metadata and compatibility fields. |
| `Sources/MentuRecipesCore/Adapters.swift` | Add adapter capability metadata. |
| `Sources/MentuRecipesCore/GitWorkspace.swift` | Add drift classification and baseline-aware quarantine. |
| `Sources/MentuRecipesCore/RunReporter.swift` | Render event summaries and analysis. |
| `Sources/mentu-recipes/main.swift` | Add `doctor`, `resume`, `retry-step`, `analyze-runs`, adapter JSON flags. |
| `docs/README.md` | Link runtime intelligence documentation. |
| `docs/recipe-schema.md` | Document new optional fields. |
| `docs/run-records.md` | Document `events.jsonl` and `state.json`. |
| `docs/security-model.md` | Document redaction and intelligence boundary. |

---

## Data Shapes

### Event Log

```json
{"id":"evt_001","run_id":"run_...","sequence":1,"timestamp":"2026-05-19T00:00:00Z","kind":"run_started","recipe_name":"release-smoke","step_label":null,"backend":null,"status":"running","message":null,"data":null}
{"id":"evt_002","run_id":"run_...","sequence":2,"timestamp":"2026-05-19T00:00:01Z","kind":"step_started","recipe_name":"release-smoke","step_label":"test","backend":"shell","status":"running","message":null,"data":{"attempt":"1"}}
```

### Quality Report

```json
{
  "recipe_name": "release-smoke",
  "score": 91,
  "findings": [
    {
      "severity": "warning",
      "code": "missing_expected_changes",
      "location": "steps[1]",
      "message": "Step may write files but does not declare expected_changes.",
      "recommendation": "Declare expected paths or add verify.git_clean_outside."
    }
  ]
}
```

### Run Analysis

```json
{
  "workspace": "redacted",
  "runs": 128,
  "success_rate": 0.86,
  "backend_summary": [
    {"backend":"shell","runs":45,"success_rate":0.98,"median_duration_seconds":8}
  ],
  "recommendations": [
    {
      "code": "add_verification",
      "message": "3 frequently failing steps rely only on provider completion.",
      "recipe_hash": "sha256:..."
    }
  ]
}
```

---

## Test Plan

### Unit Tests

- Event encoding and tolerant decoding.
- Baseline classification with pre-existing and new dirty paths.
- Doctor score and findings.
- Adapter capability rendering.
- Analyzer redaction.

### Integration Tests

- Run shell recipe and assert `run.json`, `events.jsonl`, and step outputs.
- Fail a recipe, resume it, and assert only incomplete steps rerun.
- Run expected-change recipe with pre-existing dirt and assert attribution.
- Analyze fixture runs and assert deterministic recommendations.

### Release Gates

```sh
swift test
swift run mentu-recipes scan .
./scripts/release-validate.sh --source
swift build -c release
```

For package builds, keep the existing source, stripped binary, and payload scan
requirements.

---

## Definition Of Release Ready

- `run.json` remains backward compatible.
- `events.jsonl` is written for new runs and tolerated when absent.
- `doctor` gives actionable findings with stable JSON.
- `analyze-runs` defaults to redacted metadata.
- Resume can continue a simple failed or interrupted sequence.
- Adapter capabilities are documented and tested.
- No private corpus content, private model artifacts, absolute local paths, or
  protected internal implementation names are introduced.
- Source and release artifact scans pass.

---

## Operating Principle

The intelligence belongs in the loop, not in a black box.

`mentu-recipes` should stay small enough to trust and strong enough to learn
from every run. The public runner should provide the durable evidence,
deterministic safety checks, provider-neutral contracts, and redacted aggregate
analysis. Private or cloud intelligence can plug into those contracts, but the
recipe runner remains useful, inspectable, and LLM-agnostic on its own.
