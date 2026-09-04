# Admitted execution

Admitted execution is an opt-in contract for an application that reviews a
recipe before starting it. It binds that review to resolved recipe inputs,
deduplicates an operation, and excludes other admitted operations in the same
local workspace. It does not authenticate a human or sandbox recipe code.

## Review and run

1. Run `mentu-recipes plan <recipe>` with the intended workspace, backend,
   model, variables, parallel limit, and cloud option. The result is JSON.
2. Show the recipe and its policies to the user and retain the returned digest.
3. Run the recipe with the same options, adding `--plan-digest <digest>` and
   `--request-key <unique-intent-key>`.
4. Reuse that key for duplicate submissions of the same operation. Generate a
   new key only for a new user intent, not a transport retry.

The runner compares the digest before executing hooks or creating a run. It
then uses the captured inputs that were compared, without rereading mutable
recipe or prompt files during the run. Every non-shell step must specify its
backend and model through the recipe, step, provider configuration, or CLI
options. Implicit backend detection is not available in this mode.

The digest covers recipe bytes, recursive child recipes and variables, prompt
sources and rendered content, resolved step directories, environment,
provider definitions, model/backend overrides, tool policies, hooks,
verification contracts, expected writes, retry policies, and parallel/cloud
options. Capture is bounded to 256 recipes, 32 levels, 4 MiB per input, and
16 MiB total input. Recursive recipe references are rejected.

Environment values are captured once for execution and hashed, not included in
the review JSON. Shell bookkeeping variables `_` and `SHLVL` are omitted.
Changing other inherited environment values requires a new review. A desktop
client should invoke plan and run with the same explicit environment.

The JSON contains version, digest, recipe/source/workspace, effective backend
and model per step, step digests, and child plans. It does not contain prompt
bodies or environment values. It contains local paths and model names, so it
is a local review artifact, not automatically safe to publish.

## Concurrency and idempotency

The macOS runner uses an advisory, nonblocking file lock scoped to the canonical
workspace directory. Different request keys do not bypass this workspace lock;
unrelated workspaces remain independent. Keys are hashed before becoming local
receipt filenames. Reusing a key with a different plan or operation fails.

A repeated request returns the existing run, including while it is running.
The CLI currently reports a nonterminal running record with a nonzero exit
status; consumers should read its record and must not interpret it as completed.
A conflicting request receives a busy error. Receipts survive process restart.
They live under `.mentu/runs/.admission/` and are distinct from step state.

The active marker is deliberately retained if the parent disappears, an
operation throws before finalization, or a step times out. Acquiring the OS
lock after a crash does not establish that tools launched by the old process
have stopped. Such an operation is reported as unverifiable and is not
automatically replaced. There is no force, stale-lock deletion, or timed
takeover flag. Preserve its records and establish that its tools have stopped
before a maintainer performs any out-of-band repair.

This is coordination among admitted runner operations, not filesystem
isolation. Legacy invocations, other editors, and arbitrary background jobs
launched by trusted recipe code do not participate in the lock. A shell recipe
must not detach work it expects Mentu to supervise.

## Recovery

Use `resume` or `retry-step` with the original digest and original plan options,
but a new request key for the recovery operation. Repeating the recovery request
uses that same new key. Recovery checks the saved admission and current inputs
before changing state. An admitted run cannot be recovered through the legacy
entry point. Old runs remain recoverable through their existing legacy workflow;
they are not silently assigned an approval fingerprint.

Each admitted run writes `admission.json` and `plan.json`. A parent's state
contains an additive `child_run_ids` mapping reserved before launching children.
Recovery follows that mapping. Completed child work is not launched again, and
a failed child resumes its existing run. An interrupted child with a running
record remains unverifiable. Recover children through their parent.

An explicit retry of a completed child recipe is refused. Use a new root run
intent if the objective is to perform that entire child again. For ordinary
steps, retry invalidates dependent evidence (all following steps in a plain
sequence, or transitive dependents in a DAG). Independent completed steps stay
complete. Legacy retry behavior is unchanged.

Attempt counters remain cumulative across recovery. Per-attempt stdout/stderr
files preserve previous process output; compatibility stdout/stderr files still
point to the latest attempt. Provider exceptions get a separate attempt failure
file. Run and state JSON writes are atomic.

## Limits and compatibility

- This does not implement the Mentu Commitment Protocol or a new ledger.
- Digests are integrity comparisons, not signatures or access-control tokens.
- The contract freezes declarative runner inputs, not arbitrary files read by
  tools, external executables, user CLI configuration, network responses, or
  changes made by another program. Applications needing reproducible tool
  profiles must pin and review those profiles separately.
- This is local macOS coordination, not a distributed lease or an SSH liveness
  protocol. Network filesystem lock semantics are not supported.
- `ok`, warning/bookkeeping outcomes, quarantine, and verification semantics
  retain their existing meanings. A digest does not turn a warning into proof.
- Unknown, duplicate, or missing execution options now fail instead of being
  silently ignored. Unsafe and duplicate child-node labels are rejected before
  creating output paths; use an explicit safe label for a path-based child.
- Pi and request-level inference budgets are separate additions, not provided
  by this admission contract.

## Tests

`AdmissionTests` exercises stale reviews, immutable captured prompts, repeated
intents, key conflicts, actual concurrent CLI processes, symlink aliases,
independent workspaces, unknown owners, recovery fingerprints, child identity,
attempt output, dependent invalidation, bounded recipe validation, and CLI
option errors. These tests use deterministic local shell fixtures and no models.
