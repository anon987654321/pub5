# Free compute in MASTER — implementation status

Updated 2026-11-11 against the live routing code; the keyless lanes below were
re-probed anonymously, with no credentials, on 2026-11-10/11. This document
separates implemented paths from proposals: a configured provider is not proof
that it is reachable, free at the point of use, or unlimited.

## The practical answer

There is no unlimited free inference switch. Reliable free capacity comes from
independent, provider-permitted free tiers plus transparent quota accounting,
fallback, and locally owned compute. Limits, latency, privacy terms, and
availability still apply.

## Already implemented in MASTER

- **OpenRouter free catalog.** `data/models.yml` enables live `:free` model
  discovery through the SQLite provider catalog and configures a daily
  per-model guard. The stable credential selector accepts one distinct
  populated OpenRouter credential; it never switches keys after a limit.
- **Hosted OpenAI-compatible providers.** `ModelRouter::HostedEndpoints`
  discovers models from the `openai_compatible` section. Four providers are
  verified keyless — no signup, no key, anonymous chat completions probed
  from a cold sandbox on 2026-11-10/11: LLM7 (`tier: turbo`; 100k tokens/day
  documented; chat 200 on codestral-latest and gpt-oss:20b), Kilo
  (`isFree: true`; 200 requests/hour per IP documented; chat 200 on
  kilo-auto/free), Pollinations (`tier: anonymous`; one concurrent request
  per 6 seconds documented; chat 200 on openai-fast), and OVH (explicit
  `allow` list; 2 requests/minute per IP and model documented; chat 200 on
  gpt-oss-120b). The keyless filter runs against each live `/models`
  listing on every router build, so provider-side model rotation self-heals.
  Groq, Cerebras, NVIDIA, and Z.ai carry free tiers behind a signup key and
  only join the pool when the operator configures the relevant key; quota
  and availability depend on each provider's current terms and account.
- **A user-owned OpenAI-compatible gateway.** Setting
  `MASTER_LLM_GATEWAY_URL` opts a local gateway into the same model discovery,
  health, and fallback route. Remote plaintext HTTP is refused; loopback HTTP
  is accepted.
- **Browser chat.** Existing `web-chat:` lanes are an explicitly gated,
  best-effort browser fallback. They are fragile, may have provider-specific
  terms, and are not treated as an API entitlement.
- **Local inference.** The configured Ollama lane is restricted to the
  explicit `local_model_allowlist`: gemma3:4b as the host bed and
  qwen3.5:0.8b as the phone bed (~0.6 GB, sized for devices far smaller than
  the 8 GB host). This uses the operator's hardware and has no API token
  charge, but is bounded by available RAM, CPU/GPU, throughput, and power.
- **Cooldown and health.** The existing lane quota, model skip, provider health,
  and fallback components record failures and stop repeatedly asking a lane
  that just refused or exhausted its quota. These are finite safeguards, not a
  promise that every fallback is always online.

## Quota accounting contract

`GET /api/v1/key` reports `free_model_daily_requests` as one object with
`used`, `limit` and `remaining`. It is the provider's current daily
free-model counter, not a separate allowance for each `:free` slug. MASTER
uses a fresh provider sample as the routing source; the 30-minute sample
expires and then the local fallback sums successful `:free` calls across
slugs against one conservative daily limit. The legacy
`openrouter.daily_quota_per_model` config name is retained for compatibility;
its positive value supplies that fallback.

The dashboard labels provider readings separately from per-model counts and
burn forecasts, including sample age and freshness. A stale provider sample
remains visible for diagnosis but does not steer routing. Hosted
OpenAI-compatible free endpoints retain their separately declared
per-endpoint daily caps.

Configured OpenRouter credentials are not treated as multiplied capacity.
MASTER refuses multiple distinct populated keys for one provider instead of
cycling identities after a rate, quota or budget response. It preserves
cross-provider model fallback and the provider's own reset/cooldown boundary.

## Task-aware selection versus failover

MASTER already has a task-selection layer in addition to its resilience chain:

- `ModelRouter::IntentClassification` classifies natural-language work into
  chitchat, code generation, refactoring, architecture, review, explanation,
  or exploration using deterministic patterns.
- `Review::Agent::ModelSelector` uses that classification when no explicit
  task type was supplied, then asks the existing router for the matching chain.
- `data/models.yml#routes` chooses the tier for each task. The existing
  `operation_constraints` declare hard quality floors for operations such as
  file writes, sweeps, architecture, and destructive work.
- `ComputePool` ranks eligible models using configured quality, speed, cost,
  context window, tool support, and measured success/latency/capability signals.
  Its `task_strengths` hook existed but had no declarative entries; the
  configuration now activates modest, explainable capability nudges for common
  task types. The preference is bounded to 4% per matching capability and at
  most three matches; it does not override availability, health, hard quality
  floors, quotas, or the fallback order.
- If the first model fails, the established fallback and cooldown machinery
  remains responsible for retrying another eligible lane. Selection and
  resilience are complementary layers, not competing routers.

This is deterministic task-aware routing, not an LLM judge. A separate model
judge is deliberately not inserted before every request: it would add another
provider call, latency, and an additional failure mode, and has not yet shown
that its expected savings outweigh those costs. If a later benchmark justifies
a judge, it should be opt-in and measured against this deterministic baseline.

## Local provider concurrency

A small in-process gate can enforce an operator-declared simultaneous-request
limit for an explicitly configured hosted endpoint. It shares a bucket across
models when those models consume the same provider/account concurrency budget,
rejects conflicting limits for the same bucket, and returns a typed saturation
failure after a bounded wait so existing fallback can continue. This is a
local scheduling limit, not a claim about the provider's token quota or remote
rate-limit policy. The current LLM7 keyless entry is conservatively limited to
one in-flight request; remote 429 responses and provider terms remain
authoritative. Additional endpoints should receive such a cap only when a
documented or deliberately conservative operator limit is available.

## How the newer suggestions fit

| Proposal | Status in MASTER | Decision |
| --- | --- | --- |
| Pool free models from multiple providers | Existing provider/model fallback already does this | Prefer independent supported providers and measured availability over a second router |
| Stable credential per provider | Enforced; no intra-provider rotation | Fail over across providers while respecting each provider's quota and cooldown |
| Generic local key-pool proxy | Can be reached through `MASTER_LLM_GATEWAY_URL` | Optional and operator-owned; inspect its credential, quota, and logging behavior |
| Puter.js browser bridge | Not implemented | Verify the supported interface, account terms, and user-pays behavior before adding an adapter |
| Fingerprint-rotated browser sessions | Not implemented | Do not impersonate browser identities or add jitter to defeat rate limits |
| Private GLM/mobile API proxies and token harvesting | Not implemented | Do not capture or replay browser/app credentials or depend on undocumented private APIs |
| GitHub Actions as an inference server | Not implemented | Actions minutes and platform policies are finite. Do not turn public CI into an unbounded prompt-serving endpoint; use runners for bounded repository CI/tasks instead |
| Prompt-injection-driven CI execution | Out of scope | Never pass untrusted model output into shell commands or broaden workflow permissions to obtain compute |

The seven-layer sketch is a useful way to classify possible resources, but it
is not seven independent entitlements. A local proxy may funnel several keys
into one shared quota, browser sessions may share IP/account limits, and public
CI is subject to usage rules and concurrency limits. Adding layers without
tracking the actual quota boundary would make the pool look larger without
making it more reliable.

## Future admission gates

A new provider adapter belongs in MASTER only after these questions have
deterministic answers: Is the endpoint supported and documented? Which exact
quota boundary applies? How are 429, 401/403, retry-after, and reset windows
classified? What happens when local quota state is unreadable? Does the adapter
log prompts or credentials? Is it opt-in when the provider's terms require it?
Is it covered by routing, cooldown, privacy, and failure tests?

A provider catalog entry alone is not a successful runtime probe. Any change to
the pool should preserve the existing route policy, budget limits, operation
quality floors, and evidence requirements.

## Historical status 2026-11-06: hosted free tiers

The hosted day-cap work below remains current. The key-rotation description in
the original 2026-11-06 entry was superseded on 2026-11-12: distinct keys for
one provider are not an independent quota pool and are no longer rotated.

- **Hosted free-tier day caps are enforced.** `openai_compatible` endpoints may
  declare `daily_quota` (groq 14,400; cerebras 100 — the same figures their
  blocks already stated). `Io::ModelQuota` tracks `<name>:<model>` lanes
  against their endpoint's cap, so an exhausted free tier is filtered by
  `LaneSelection` and `ComputePool` instead of being retried into 429s. An
  endpoint without a documented day cap (nvidia, llm7) stays untracked rather
  than guessed. The OpenRouter conservative-counter rule is unchanged: the
  hosted counter counts calls, not multiplied capacity.
- **Historical credential rotation (superseded 2026-11-12).** The earlier
  implementation cycled credentials within one provider after limit responses.
  The current selector refuses multiple distinct populated credentials and
  keeps one stable key. Failover crosses to another eligible provider; it never
  changes account identity to evade a shared quota or a configured key budget.
- **Replicate chat lanes stay out of the ranked pool.** Score rows for the
  `replicate_chat` slugs were proposed and withdrawn: without a `model_defs`
  row `ComputePool#candidate` drops a lane from the ranking, so the rows would
  have made paid per-call lanes selectable by rank for the first time
  (test/test_compute_pool.rb holds the exclusion).
