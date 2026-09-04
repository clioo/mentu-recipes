# Pi and inference budgets

The opt-in Pi adapter drives a real installed Pi coding agent, including its
tools and explicitly selected skills. It is not the `openai-chat` adapter with
a different label. Existing backends and recipes without a budget are unchanged.
This adapter requires Pi 0.84.1 or newer and Node.js 22.19 or newer. The fixture
suite pins Pi 0.84.1; newer versions must continue satisfying the same contract.

## Configuration

Use a named provider with `api: "pi"`, an explicit OpenAI-compatible Chat
Completions base URL, an exact model identifier and a provider-specific env or
vault key. The runner does not discover models, select a fallback, or inherit
Pi's global provider configuration. Inspect your server's model catalog first.

```json
{
  "name": "pi-inspect",
  "providers": {
    "local-agent": {
      "api": "pi",
      "base_url": "http://127.0.0.1:8080/v1",
      "api_key_env": "LOCAL_AGENT_KEY",
      "model": "your-exact-model-id",
      "max_tokens_field": "max_tokens",
      "context_window": 32768,
      "skills": []
    }
  },
  "inference_budget": {
    "max_requests": 8,
    "max_concurrent_requests": 1,
    "max_request_bytes": 65536,
    "max_total_input_bytes": 524288,
    "max_output_tokens": 1024,
    "max_duration_seconds": 300
  },
  "steps": [{
    "label": "inspect",
    "backend": "local-agent",
    "prompt": "Read README.md and describe the project. End with INSPECTED.",
    "allowed_tools": ["read"],
    "completion_keyword": "INSPECTED",
    "timeout": 120,
    "max_retries": 0,
    "verify": {"git_clean_outside": []}
  }]
}
```

`max_tokens_field` accepts `max_tokens` (default) or `max_completion_tokens`.
Only that field is forwarded, capped by the smaller step/global output limit.
The Responses API field `max_output_tokens` is not forwarded to Chat Completions.
`context_window` is Pi model metadata, not proof of server capacity.

Allowed/denied tools use Pi names: `read`, `bash`, `edit`, `write`, `grep`,
`find`, `ls`. Without an allow-list the default is `read,bash,edit,write`;
an empty list disables tools. `skills` lists explicit paths loaded with Pi's
`--skill`; automatic skill/context/extension discovery is disabled. Skills and
tool-readable files remain live files, so callers requiring immutable inputs
must snapshot them separately. Reasoning overrides are not supported; the
isolated profile requests thinking off.

## What is bounded

An embedded Node transport binds an authenticated loopback listener for Pi and
forwards only the configured model's Chat Completions route. It rejects other
models, extra completions, redirects and non-streaming requests. It records a
durable reservation before each network attempt, including tool-loop requests.
Connection failures are conservatively charged; a reservation does not prove
that a remote server accepted or completed a request.

The root budget is shared across steps and child recipes. Counters and the
original deadline survive resume/retry. A child cannot replace the policy;
recovery cannot assign a new budget to a previously unbudgeted run. A recovered
budget requires its original evidence. If a run failed before initializing
that evidence, start a new explicitly identified run, not a silent reset.
One budget currently binds one endpoint, model and token-field combination.
Mixed-model workflows require separate explicitly budgeted runs.

Limits apply to request count, concurrent in-flight requests, serialized input
bytes per request and total, output tokens per request, and elapsed duration.
All are required positive integers. Request bodies are at most 16 MiB, duration
at most seven days, requests at most one million, output cap at most 2^31-1,
and total input at most JavaScript's safe integer limit. These validation ceilings
are not recommended operating budgets. Byte limits are not token measurements.

Pi runs with a private profile, no global API credentials, no automatic retry,
compaction, extensions, context files or update checks. Shell and Pi steps are
allowed within a budgeted run; other agent/HTTP backends and cloud evaluation
are refused. Transport errors stop the budget. No key/model/cloud fallback
exists. Unknown ownership or unresolved reservations fail closed, with no stale
lock takeover. A shortened or missing stream is not successful completion.

The real provider key is available to the transport, not the Pi child. The
child receives only a random loopback token. This is **not an OS sandbox**:
user-approved shell hooks, tools, skills and local processes retain their normal
permissions. They can bypass the managed transport if allowed to make their
own network calls. Run untrusted code in an external sandbox. Ledger checks
detect missing/inconsistent evidence, not malicious edits by the same OS user.
The transport bounds requests, not the server's physical memory or billing.

## Evidence and failure semantics

The run record's optional `inference_budget` references the shared directory.
`budget.json` contains reservations, deadlines, counters, outcomes and provider
usage; `budget-identity.json` guards against recreating missing counters. Each
`pi-<id>/inference.json` contains that attempt's request IDs, exit result, model
and token totals. Usage absent from any response is reported as unknown, not
estimated from bytes. Preserve these files together with the ordinary step
records. Do not publish private launch profiles or prompts.

The adapter also requires a final successful Pi assistant completion. An
`agent_end` with an error, abort or length limit is not enough, even if Pi exits
zero or the text includes the recipe's completion keyword. Process timeouts
terminate the owned Pi process group. These are local execution records, not
formal Mentu Commitment Protocol records.

## Validation

`swift test` includes deterministic ledger/transport tests. With Pi installed,
it also exercises real read/write tools and an explicit skill against a local
scripted HTTP provider, without model inference or credentials. Tests cover
child/resume budgets, missing evidence, concurrent processes, output-field
mapping, provider failures, redirects, truncated streams and timeouts. These
tests validate integration mechanics; they do not measure a model's quality.

The real-CLI suite skips when Pi or Node is absent. For a mandatory integration
job, provision Node 22.19 or newer, install the pinned fixture version with
`npm install --global @earendil-works/pi-coding-agent@0.84.1`, and run
`swift test --filter 'PiCLIFixtureTests|PiTransportTests'`. The existing CI
workflow is unchanged; a test job without Pi does not prove real-CLI acceptance.

The JavaScript sources are embedded in Swift so the existing single-binary
release format and installer do not acquire resource-bundle dependencies.
