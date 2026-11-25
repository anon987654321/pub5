# MASTER

MASTER is pub5's agent runtime and engineering constitution. It interprets tasks, applies the Laws, routes models and tools, and coordinates checks and repairs. RAILS owns the applications; OPENBSD owns hosts and deployment; STUDIO owns creative and media work.

## What the name means

MASTER names two related ideas. **Mastery** is the disciplined practice of learning a subject well enough to exercise sound judgment: research, compare, experiment, measure, correct and verify. It is an aspiration, not a claim of infallibility. **Master** also names an authoritative source in the traditional DNS primary/secondary model. The name joins the two: authority should be earned through mastery and constrained by evidence. Current DNS standards use *primary* and *secondary*; older DNS material uses *master* and *slave*. This README uses the current protocol terms while explaining the historical connection ([RFC 9499, DNS Terminology](https://www.rfc-editor.org/rfc/rfc9499.html)).

The DNS analogy is precise but limited. Within one DNS zone, a primary nameserver owns the canonical writable zone data. Secondary nameservers receive validated transfers, keep serving authoritative answers from their copies, and do not become independent writers of the primary data. Serial numbers and refresh checks make stale copies detectable. A secondary that cannot prove freshness is not silently treated as current.

Apply that pattern to **each concern**, not to the repository as a whole. `MASTER/data/soul.yml` owns identity and source precedence; `MASTER/data/laws.yml` owns individual Law records; executable Laws and gates implement them; tree contracts define local boundaries; Git history records provenance. `RAILS`, `OPENBSD`, `STUDIO` and `BIZ` remain authoritative owners of their own products, hosts, creative work and documents. RAILS is not a replica of MASTER, and MASTER is not the writable source for every application detail.

The rule is **one canonical owner per concern, with capable consumers and verifiable projections**. Generated agent entrypoints, compact agent briefs, runtime prompts, generated token files and deployed copies consume their owners. They must not become competing writable sources. A mismatch, missing source, stale digest or unmeasured projection is visible and inconclusive; it is never silently promoted to authority.

## Mastery in the working loop

Research should widen the set of plausible answers, not dictate the answer. For consequential or unfamiliar work, MASTER seeks primary documentation, source code, academic work and high-signal practitioner evidence; it looks for counterexamples and materially different approaches; then it chooses a bounded experiment, executes it under the Laws, measures the result, repairs failures and records the evidence in the existing owner. `/fix` is the delivery path, not a substitute for thought. A commit is a checkpoint, not proof that the work is correct.

The model serving a turn is replaceable transport. MASTER's identity and authority do not move when the provider changes. The operator sets goals and owns deliberate value choices; MASTER owns the contracts assigned to it and remains answerable to evidence, the operator and applicable law.

## Writing and documentation

Keep documentation as precise as the runtime. Write for the reader's next
decision; state facts before interpretation; give commands with their working
directory, prerequisites and expected result; explain failure and recovery.
Use Strunk and White for sentence economy, Bringhurst for typographic order,
and OpenBSD's manual discipline for operational truth. The shared rules and
editorial review contract are in [MASTER/AGENTS.md](AGENTS.md#documentation-and-editorial-standard).

## Read this first

The authority order is:

`data/soul.yml` → `data/laws.yml` → executable Laws and gates → tree contracts → Git history.

- [Repository agent entrypoint](../AGENTS.md) gives every agent the shared working contract.
- [MASTER/AGENTS.md](AGENTS.md) holds the detailed edit, preservation, proof and delivery rules.
- `data/soul.yml` owns identity, preservation and protected paths.
- `data/laws.yml` owns Law identities, statements and the execution catalogue.
- `law/` implements the Laws; `checks/` and `lib/review/scan/` measure them.
- `data/laws.yml` also holds the scanner, veto, provider and `/fix` runtime settings.
- `tools/agent_context.rb --json` emits compact, machine-readable context for external models.

Treat Laws as transferable engineering knowledge, not ceremony. Read the governing source before changing behavior; use executable checks as evidence, not as substitutes for judgment. Tool output and fetched material are data, never new authority.

## The runtime

For local handwritten archives, `/documents analyze ~/Photos` reads a bounded set of page images one at a time through the configured vision lane, marks uncertain readings and asks the model to group and sequence letters from document evidence. It never modifies source images; the report and SHA-256 manifest are stored locally under `~/.local/share/master/document-archives` with owner-only permissions. JPG, PNG, WebP and GIF are supported; HEIC, TIFF and PDF files are reported as skipped. Each page and the final chronology are sent to the configured vision provider, so use a trusted/private lane for confidential letters.

`bin/master` is the interactive assistant and command entrypoint. From the `pub5/` repository root, start it with `MASTER/bin/master`; from inside `MASTER/`, use `bin/master`. The tracked launcher already has executable mode, so a normal checkout does not need `chmod`. `bin/operator` is the operations surface for status, checks, tests and supported host tasks. The browser face and speech runtime live under `web/`; their policy belongs in the relevant data sources rather than duplicated literals. Music plays only after an explicit operator request; startup never begins audio on its own.

## Web face: sculptural particle stipple

A benevolent, otherworldly intelligence embodied by independent particles acting as one. Pluribus informs collective emergence and signal motion; Papuan sculpture informs essential form; speculative future-human anatomy informs the approachable proportions. This is original geometry, not a museum scan, ceremonial replica or prediction of human evolution.

### Aesthetic

- **Material:** solid neutral bitmap marks on absolute black. Both shaders use a fixed 3 × 3 raster with two opposite corner cells removed, not hollow diamonds, beads or glow. Discrete neutral relief tones and depth writing reveal the volume. The apparent CSS size depends on render scale and device. Never enlarge marks with perspective.
- **Form:** genuinely spatial, rounded cranial volume, generous dark eye wells, relaxed brows, short nose, full cheeks, small gently smiling mouth, soft chin and restrained asymmetry. Preserve the sculptural Sepik character without ornament. Read as curious, intelligent and approachable, not cartoonish.
- **Composition:** void is structural. Prefer organic separation, curved relationships, sparse peripheral marks and the fewest anatomical cues that preserve recognition from front, profile, rear and three-quarter views. No fingerprint decoration, solid skin, wireframe, gradients, glossy surfaces or decorative glow.
- **Motion:** organic flow, bounded rotational flow, travelling signals and staggered cohort convergence. Stable carriers retain identity through transformations; a temporary subject returns to the canonical portrait. Gesture, gaze, blinking, nods and soft settling should communicate intent, not perpetual activity. Reduced motion resolves to the same meaningful form.
- **Acceptance:** these are design requirements, not claims that every adapter or behavior already conforms. Compare actual multi-angle browser captures against the operator-approved reference, including mobile scale; reject flat relief, excessive detail, occluded apertures, mechanical rows, noisy idle behavior and unmeasured performance claims.

Five original studies rotate on new conversations and remain stable on reload. Conversational characters remain independent of their geometry. Each study uses the same carved volume, carrier population and material; temporary subjects reuse the primary field.

### Runtime and ownership

FaceState drives FaceWorld, CLI, 2D/ASCII fallback and voice timing. `data/tokens.yml#tokens.face_interface` owns visual and semantic parameters; Ruby reads them through `lib/face.rb` and the browser receives `MASTER_FACE_CONTRACT`. Dynamic state belongs to `MASTER_FACE_STATE`. `data/face_masks.yml` owns selection and character metadata; `data/laws.yml` owns aesthetic constraints.

`web/public/face_mask_profiles.js` samples deterministic front, rear and interior geometry through one implicit volume with carved apertures. `face_world.js` maps semantic subjects into the existing carrier field and orders arrival stages. `face.part2.txt` and `face_stipple_system.js` implement the primary material and an exclusive stipple preview (`?stipple=1` or `?playground=1`). Direct subjects never overlap the preview. The default path allocates no second stipple geometry and hides the spatial world and sparse overlays while native portrait geometry owns the canvas. The explicit material laboratory starts with the unmasked portrait. The six runtime sources are joined at build time and imported directly. The existing asset manifest and `FaceAssets.versioned` fingerprint public assets. Do not introduce a second state vocabulary, unbounded population, independent animation clock or product-wide particle treatment. Existing sparse/proxy adapters must be audited for material and carrier-budget conformity; their presence is not proof of single-population rendering.

The web runtime is conversation-only. The independent terminal retains OpenBSD-style factual output. Operator commands, scheduling and filesystem access remain local CLI concerns.

### State and movement

| State | Membership | Force |
|---|---|---|
| idle | transitional | residual |
| listening | transitional | ripple |
| thinking | turned | gather |
| working | turned | gather |
| speaking | turned | ripple |
| warning | transitional | residual |
| error | unturned | fragment |
| ready | locked | settle |
| sleeping | unturned | residual |

State supplies the cause of motion. Listening receives a signal; thinking gathers; speaking sends a signal from the mouth; warning loosens cohesion; error fragments; recovery restores the portrait. The canonical settle interval and device budgets live in tokens, not new constants. Reduced motion and visibility policy apply to all adapters. No autonomous ornamental movement in the accepted resting pose.

### Semantic subjects

The face is the opening identity and the resting state. A completed assistant
reply is sent through the canonical `assistant:visual-subject` event. The event
may contain a `visual_subject` descriptor, or the renderer may infer one of the
small set of supported object kinds from the finished reply. For inferred
subjects, repeated mentions rank ahead of one-off mentions and first mention
breaks ties. An explicit descriptor always wins. A descriptor is accepted only
when its kind is in
`face_interface.spatial.semantic_subject.kinds`; its confidence is bounded,
its label is sanitized, and its ordered feature list is intersected with that
kind's allowlist. Unknown or low-confidence subjects leave the portrait intact
instead of inventing a shape.

Example event payload:

```json
{
  "text": "A suspension bridge carries traffic across a wide span.",
  "visual_subject": {
    "kind": "bridge",
    "confidence": 0.91,
    "sequence": ["deck", "towers", "cables", "piers"]
  }
}
```

For subjects outside the built-in catalogue, the same event accepts
`kind: "custom"` with up to eight named parts. Each part selects one of five
bounded primitives — `box`, `sphere`, `ring`, `cylinder`, or `beam` — and
may supply a centre and half-size vector in normalized face space. The browser
sanitizes names, rejects duplicate/unknown keys and unsupported primitives,
clamps centre and size values to the token-defined bounds, and accepts only
the three fixed beam axes. It never evaluates model code or arbitrary geometry.
The part sequence is the reveal sequence, so an unfamiliar explanation can
still resolve as a small, ordered construction rather than an unstructured
cloud.

Example: a bicycle is represented as a frame beam, two wheel rings, and a
handlebar beam:

```json
{
  "text": "A bicycle balances on two wheels with a frame, fork and handlebar.",
  "visual_subject": {
    "kind": "custom",
    "label": "bicycle",
    "confidence": 0.88,
    "sequence": ["frame", "rear-wheel", "front-wheel", "handlebar"],
    "parts": [
      { "key": "frame", "primitive": "beam", "axis": "x",
        "center": [0, 0, 0], "size": [0.42, 0.035, 0.035] },
      { "key": "rear-wheel", "primitive": "ring",
        "center": [-0.38, -0.18, 0], "size": [0.20, 0.20, 0.025] },
      { "key": "front-wheel", "primitive": "ring",
        "center": [0.40, -0.18, 0], "size": [0.20, 0.20, 0.025] },
      { "key": "handlebar", "primitive": "beam", "axis": "z",
        "center": [0.30, 0.36, 0], "size": [0.035, 0.035, 0.22] }
    ]
  }
}
```

The primary face field receives the object coordinates in its existing
`scatter` attribute and uses a per-carrier `semanticStage` to reveal features
in sequence. It does not allocate another renderer, animation loop, or particle
pool. The bounded FaceWorld proxy is a compatibility path only when the primary
scatter interface is unavailable; it consumes the existing world-point share.
Normal motion stages the transition. Reduced motion resolves directly to the
same final geometry without an animation. After the configured quiet interval,
the subject restores to the selected conversation mask, or the carved-field portrait when no mask is available. Unknown or rejected subject descriptors restore that same identity. The canonical face persists across conversations. Subject geometry is schematic unless backed by measured data.

This separation is deliberate: identity is stable, the subject is temporary,
and movement has a reason. The face must remain readable before, during and
after an explanation; an unknown object is not an excuse to replace it with
decorative noise.



### ASCII controls

## ASCII sculpt controls

The terminal and browser render the same perspective-correct, lit triangle mesh as
ASCII, with the contract's character ramps ordered by measured ink density. The
browser keeps the existing single frame loop and offers the same practical controls
as the STL-to-ASCII reference:

- `c`: cycle the contract's sculpt, high-contrast and fine-detail character ramps.
- `m`: reverse or restore the ASCII tone ramp. This does not invert the page or
  recolour the underlying WebGL scene.
- `r`: pause or resume automatic rotation; dragging horizontally on the face
  canvas manually changes the ASCII head's viewing angle.
- `?face_ramp=high_contrast`, `?face_ink=light` and `?face_rotate=0`: set those
  preferences directly; `?face_chars=MASTER` supplies a custom printable-ASCII ramp.

In the terminal, `MASTER_FACE_RAMP=high_contrast`, `MASTER_FACE_CHARS=MASTER`,
`MASTER_FACE_MODE=light` (reverse the tone ramp), `MASTER_FACE_ROTATE=0`, and
`MASTER_REDUCED_MOTION=1` select the equivalent appearance options. Named ramps live in `MASTER/data/tokens.yml`; the browser and
Ruby renderer do not carry separate copies of the ramp definitions. The ordinary
ramp, default ink and pose remain unchanged so the existing golden frames stay valid.



### Verification

From the repository root:

```sh
node --test MASTER/web/test/face_boot.test.mjs MASTER/web/test/face_stipple.test.mjs
```

From `MASTER/`, run `bundle exec rake test` and `bin/check --profile=operator`. Capture default, `?stipple=0` and `?playground=1` at narrow and wide viewports, with reduced motion on and off. Inspect front, three-quarter, side and rear geometry; shader compilation, console errors, context recovery, speech, subject morphs, cohort continuity and actual point budgets. The playground snapshot distinguishes JavaScript render-call cadence from GPU completion or validated FPS. The existing council should critique form, spacing, friendliness, state communication, accessibility and cost through convergent deliberation; missing reviewers or captures are inconclusive. A source commit is not deployment evidence.

### Research references





## Terminal type and accessibility

MASTER does not set the terminal emulator's font size. PuTTY and Termux own
that setting, so choose a large fixed-width face there. Start at 20–22 pt in
PuTTY, then increase it until the text is comfortable at normal viewing
distance. Larger type is a supported operating preference, not a layout error.

Install the JetBrainsMono Nerd Font Mono TTF from the
[official Nerd Fonts release archive](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz)
before selecting it. The RAILS WOFF2 files are browser assets, not terminal
font installers.

- **PuTTY:** open *Window → Appearance → Font*. Choose the installed
  JetBrainsMono Nerd Font Mono face or another fixed-width face and set its
  point size. Save the session so the choice persists. PuTTY documents the
  [font and size selector](https://www.puttyssh.org/0.78/htmldoc/Chapter4.html).
- **Termux:** pinch to zoom the terminal text. To choose a font, long-press the
  terminal, open *More → Style → Choose Font*. A custom TTF may live at
  ~/.termux/font.ttf; run termux-reload-settings after changing it.
  See the [Termux terminal guide](https://github.com/termux/termux-tools/blob/master/doc/termux.1.md.in)
  and [Termux:Styling](https://github.com/termux/termux-styling).

Keep terminal output legible at every size. Use one factual event per line,
allow the emulator to wrap long text, and never pad fields into fixed columns.
MASTER uses semantic ANSI colour only on an eligible TTY; pipes, NO_COLOR
and dumb terminals receive plain text. Nerd Font private-use icons are optional
and never replace words or ASCII-safe output. The browser uses locally served Geist Mono, with JetBrains Mono as fallback,
at 20px on desktop and 16px on narrow screens, 1.5 leading and a 66ch measure.
The face occupies its own region above the scrollable transcript. The native
terminal may select Geist Mono or keep JetBrains Mono Nerd Font for optional glyphs.

These choices follow Strunk and White's directness and Bringhurst's hierarchy,
measure and rhythm: the reader should see the information first, not the
interface's ornament. They also follow inclusive practice: the operator owns
the size that makes the terminal readable.

A new interactive launch can recover an abandoned same-host MASTER prompt after
two hours without session-transcript activity. It acts only when the OS confirms
that the exact MASTER process is the sole lock holder, is sleeping or idle, has
no child work and still has a terminal; it sends that process TERM and waits for
the OS lock to clear. It never unlinks the lock file or reclaims daemon/control-
plane locks. Set `MASTER_LOCK_IDLE_RECLAIM_SECONDS=0` to disable the lease, or
set a different positive number of seconds. Recovery is attempted on the next
lock acquisition, not by the read-only `bin/master --status` command.

The ordinary CLI boot uses native workspace tools and does not start an npm MCP server or play a startup sound. The browser face retains its explicitly gesture-gated sound asset. Optional MCP servers stay in `data/mcp_servers.yml` and are disabled unless enabled there. Set `MASTER_BOOT_TIMING=1` for one launch to print timings for Ruby/dependency preparation, voice services, the builder and the remaining boot phases; ordinary startup stays quiet. Provider reachability and the wider YAML inventory run without holding the prompt.

### STUDIO likeness workflow

Ask MASTER in ordinary language to check a subject's photographic readiness, compare the available LoRA inference profiles, prepare a training preflight, or review the latest completed portraits. MASTER routes those requests through STUDIO's existing LoRA API; it does not duplicate the trainer, consent gate or photographic rubric.

Readiness and profile comparison are read-only: they make no provider calls, upload no photographs, start no training and generate no images. Profile comparisons report the configured settings only. The four profiles remain `UNBENCHMARKED` until the same approved model, scenes, seeds and independent holdout set have been compared and a person has reviewed the full-size results.

Reviewing an existing series creates private local HTML/JSON review artefacts from the latest recorded renders and independent holdout photographs. It does not generate candidates, upload images or approve a likeness. Missing holdout photographs, consent evidence or training prerequisites remain explicit blockers. Candidate generation and LoRA training are separate paid operations and must never be inferred from a readiness or comparison request; training requires an explicit spend ceiling and operator approval. Publication permission is separate again.

The CLI lists canonical commands once. Compatibility spellings route to their owner: `/models` means `/model list`, `/tools` means `/capabilities`, and `/tts` means `/voice`. Use `/help <alias>` to open the owning page. `/doctor tools` is a separate diagnostic for unresolved tool outcomes.

The core execution path is `lib/core/`: an admitted effect passes through Constitution before World dispatches it. Keep capabilities, validation and compensations at that boundary. Extend an existing owner before adding another wrapper, registry or helper.

## One repair workflow

`/fix` is the one governed pipeline command. Its `--mode=` presets are:

- `repair` (default): observe, critique when configured, repair, re-observe and verify; runs read-only unless the caller explicitly supplies `--apply` with an explicit mode and named target. Every requested repair lane records the canonical Law × stream × surface assessment and a universal quality receipt (engineering, editorial, visual, experience and operations). The ordinary `code` and rendered-target `standard` lanes also run bounded continuous polish discovery across code, prose, UI source, YAML structure and notation; candidates enter the same improvement repair, transaction and proof path. The additional mechanical `PolishLens` intake is opt-in with `MASTER_BACKLOG_AUTORUN=1`, restricted to exact files already owned by one tree's active pass, and feeds that same improvement stage rather than creating a second queue. The improvement council also reviews comprehension, navigation, interaction choreography, accessibility, privacy and trust, localization, resilience, provenance, perceived performance and cross-product continuity while preserving each product's identity. These are review dimensions, not automatic claims of acceptance. A plain `/fix MASTER` selects the focused `master` lane: code review, read-only repair preview, continuous polish discovery and rendered review of MASTER's own web face only. A plain `/fix RAILS` selects the rendered `standard` lane; ordinary non-rendered targets retain the `code` lane.
- `audit`: read-only tree review: first-read, execution trace, non-persisting backlog review when due, structural review, scanner/structural preview, typography and principle map, council critique, and the existing per-tree repo-sweep probes (RepoEcology (history cache disabled during audit), the full SprawlCensus, Cohesion file-family and repeated-method-shape reports, DupCensus, data/law reach, namespace, design baseline and tree-specific checks). Probe output distinguishes subprocess completion from instrument findings; exit 0 is not a Law PASS. Repair is replaced by preview; tree/backlog/structural review proposals are not persisted.
- `visual`: read-only style pass (`--dry-run --only=style`).
- `elevate`: the existing improvement lane (`--lane=elevate`).
- `all`: research, architecture, rendered RAILS review, grouped visual repair for RAILS targets, ordinary code-law repair, every improvement domain (code, prose, visual, structured configuration and music), ideation and restructuring; read-only by default; writes require explicit `--apply` with the same mode and a named target, and remain subject to existing budgets.

`--read-only` and `--dry-run` are unconditional no-write requests and override `--apply`. Audit and visual modes cannot be made write-enabled by also passing `--apply`. A mutating request must name its mode and scope, for example `/fix --mode=repair --apply MASTER/lib/cli`; a bare `/fix` is preview-only, and `--apply` without a mode or target is refused. Elevate and all reuse the existing file, pass, stall and resource budgets; they do not bypass sacred-path, rendered-value, transaction or restructuring proof gates.

The existing compatibility spellings rewrite to the one dispatcher: `/audit`, `/review`, `/critique` and `/council` select audit; `/scan` selects the read-only repair preview (`--mode=repair --dry-run`); `/visual` and `/style` select visual; `/elevate` and `/map` select elevate; `/all`, `/workflow`, `/triad`, `/sweep`, `/through` and `/self` select all. Use `/fix --mode=repair|audit|visual|elevate|all` for explicit mode selection. New instructions and scripts should call `/fix` directly.

The Kernel serializes a run, records its lifecycle, and delegates convergence and Law-level repair. Runs are bounded and resumable; a stopped or interrupted run is not a successful one. Ordinary per-file repairs use `Fix::Transaction` for staged writes, rollback and delivery. Multi-file restructuring uses the explicit snapshot, proof and undo path in `Fix::Restructure`. Those are distinct recovery contracts; do not describe one as the other. The canonical execution owners are the Ruby implementations under `lib/core/`, `lib/fix/kernel/` and `lib/execution.rb`; tests pin the public ownership and recovery boundaries.

The run footer includes a per-run file outcome docket for files that entered the repair adapter. The durable assessment artifact separately enumerates every eligible scanner path as scanned or unmeasured; that is scanner coverage, not a Law PASS or a census of rendered behaviour. The Law × stream × surface matrix remains the compliance record. Its quality projection reports engineering, editorial, visual, experience and operations separately. `compliance_status` must be PASS before repair can finish DONE; `overall_status` also records external evidence, which remains INCONCLUSIVE until document rendering, assistive technology, live-host, listening or qualified business/legal review is actually supplied.

Run one tree at a time unless evidence establishes a cross-tree dependency. From `MASTER/`, the normal entrypoints are `bin/master /fix MASTER`, `bin/master /fix RAILS`, `bin/master /fix OPENBSD`, `bin/master /fix STUDIO` and `bin/master /fix BIZ` for document production.

## Measure before declaring done

From `MASTER/`, the read-only architecture and layout checks are:

`bundle exec ruby checks/runner.rb --scan-only architecture layout_suite`

The full configured RAILS check chain is:

`bin/operator check --scan-only --tree=RAILS`

The separate constitutional Law-corpus scan is:

`bundle exec ruby checks/runner.rb --scan-only constitutional_scan`

The serial diagnostic test run is:

`MASTER_TEST_JOBS=1 bundle exec rake test`

A scan-only run does not authorize edits. Source checks do not prove rendered behavior, accessibility, runtime health or deployment; run the evidence required by the changed surface. Report skipped and unmeasured work as such. Never turn a missing instrument, unrun test or unavailable host into a PASS.

### Measure before making /fix faster

`MASTER_BOOT_TIMING=1` records the existing startup stages. The `review:complete` event includes `phase_elapsed_s` for the measured Pass boundaries (`observe`, `critique`, `converge`, `style` and `map`). These are accumulated durations, not a decomposition of every operation: `observe` includes its current observation work, and `converge` includes the FixLoop lifecycle. Do not rename either as a separate scan, model, verification or delivery measurement. Missing stage timings mean unmeasured, not zero.

Before changing performance policy, compare the same pinned target, runtime, resource conditions and proof population. Record the actual files and Law assessments measured, elapsed time, memory/CPU and any unavailable reviewers. Reuse cached work only while its source, Law, scope, authority, toolchain and adapter digests remain current; the existing finding cache and FixPlan already own those checks. Keep deterministic repair before model work, retain the stream's bounded worker and resource limits, and preserve full-target recollection after incremental repair. A council or rendering result that cannot run stays INCONCLUSIVE. Reject any speedup that omits a file, Law, surface, human assessment or required proof.

## Configuration has owners

- `data/providers.yml` and `data/models.yml` own provider and model configuration; `lib/io/model_quota.rb` owns quota measurement and fallback decisions.
- `data/voice.yml` owns speech runtime configuration.
- `data/tokens.yml` owns visual values; `data/laws.yml` owns minimal-interface, visual, dialogue and constitutional policy.
- Generate the current typography reference without creating a second source: `ruby MASTER/tools/design_tokens.rb --type-spec` reads the named role tokens, product dialect and measured accessibility limits directly from `data/tokens.yml`.
- `data/council.yml` owns council personas, presets and the juror and judge prompts; the default hard-critique preset is `general_critique`, and the prose contract on those prompts applies to English and Bokmål alike.
- `data/affiliate_sources.yml` owns the affiliate source registry.

Do not copy their values into code, prompts or documentation when a reader can use the canonical source. Secrets belong in the runtime environment, never in Git.

Relevant optional settings include `MASTER_BACKGROUND_SCAN=1` for opt-in background scanning, `MASTER_TEST_JOBS=1` for a single test worker, `MASTER_LLM_RECORD=1` for trajectory recording, `MASTER_LLM_GATEWAY_URL` and `MASTER_LLM_GATEWAY_KEY` for a hosted gateway, plus the runtime selectors `RUBY_BOX` and `MASTER_JIT`.

The full builder self-test is off during ordinary startup. Run `bundle exec rake selftest` for the complete Law scan, set `MASTER_BOOT_SELF_TEST=1` to run it in the background during startup, or set `MASTER_STRICT_BOOT=1` to run it synchronously and fail boot on a finding. Streaming `/fix` uses `MASTER_FIX_STREAM_WORKERS` (default 3, integer from 1 to 8); set `MASTER_FIX_STREAM=0` to disable the worker stream.

`MASTER_AUTOFIX=1` changes the repair policy for an explicitly invoked `/fix`; it does not start a background whole-tree mutator. Boot-time unattended repository work enters through `MASTER_BACKLOG_AUTORUN=1`, the owner-registry executor, which revalidates each task's exact paths, task digest, bounded acceptance command, lease and terminal proof. Missions have no lifetime attempt ceiling: transient failures use capped exponential backoff, exhausted providers wait for a slower re-probe, permanent failures terminate only that mission, and ambiguous outcomes require human review. The backlog executor records parked item outcomes in the same private state store as mission records (`MasterPaths.fix_state`; local `.master/backlog-executor.jsonl` when no remote identity is available) and advances to independent eligible work under the same single-writer lease. It reads prior checkout-local receipt files during migration, but writes new outcomes only to the canonical store. Transient parked items become eligible again after their retry time or a scope change; permanent and ambiguous outcomes remain parked until the operator explicitly releases them with `MASTER/bin/operator backlog resume <item-id>`. Use `MASTER/bin/operator backlog status` to inspect ready and parked work without exposing task prompts.

## Outbound network boundary

Every server-side fetch is an SSRF boundary, even when its URL appears to name
a trusted provider. `Master::Io::SsrfGuard` owns MASTER's public HTTP boundary.
`SsrfGuard.request` parses a clean URL, accepts only HTTP on port 80 or HTTPS
on port 443, rejects credentials and fragments, validates DNS-name shape before
resolution, and classifies every returned A and AAAA address. One private,
loopback, link-local, multicast, translated, documentation or reserved answer
rejects the whole set. The chosen public address is pinned into
`Net::HTTP#ipaddr`; the original hostname remains in place for TLS SNI,
certificate verification and Host. Environment proxies are disabled because
they would bypass the pin. The shared request path streams under a byte cap,
bounds the total operation and sets explicit connect, read and write timeouts.

A redirect is not permission to make a second request. `WebBrowse` checks its Location target before handing it to Chromium, then
intercepts and pins the resulting request again. `ExternalAudit` follows only
bounded same-host redirects and re-resolves and pins every hop; it refuses
cross-host redirects and HTTPS-to-HTTP downgrade. Other clients do not follow
redirects implicitly.
Response bodies, DNS lookup, connection phases and operation deadlines remain
bounded. Local daemon probes are a deliberate separate policy, not public-web
fetches.

The Soulseek adapter lives in `plugins/soulseek/` and talks to an operator-owned
slskd instance. Plain HTTP is restricted to loopback; remote instances require
public HTTPS on port 443 through the same pinned-address guard. Its API key is
process-environment-only. Search, manifest comparison, local inventory, catalogue
building, quality triage and duplicate reports are read-only. Catalogue export
requires an explicit destination and consent; a download queue request is one
exact search result and one file, with explicit consent and a declared rights
basis. Bulk acquisition is disabled.

The initial collection-export audit is stored as `data/music_collection.yml`.
It records path counts and category summaries from the supplied `0day.txt`,
`samples.txt` and reggae snapshot. It is a dated path-list baseline, not a live
catalogue or a verified unique-track count. Keep those source exports separate
until their storage locations are known, and build the canonical catalogue from
the actual music folders.

`ROBUSTNESS_outbound_fetch_is_pinned` in `data/laws.yml` makes this a
repository-wide robustness requirement. Keep new HTTP clients on the guard;
never add a validate-by-hostname step followed by an unpinned connection.

## Doctor, first hour and failures

`bin/operator doctor` checks the checkout/host and reports one line per area: disk, Ruby,
bundle, hooks, worktrees, Git state, model lanes, stray processes and `.master/`
writability; add `--remote` for vm23. `OK` means fine, `warn` means it works
but is about to cost you, and `FAIL` stops work and carries the fix on the same line.

`MASTER/bin/doctor` is the runtime report (boot, provider/model, voice
and face capability); the interactive `/doctor` adds security and capability
context. This is separate from the checkout/host doctor above. Neither doctor
is the repair command.

For ordinary work, start `bin/master` and enter `/fix [TREE]`. That command
owns repair and scope-aware proof; do not append a full verification profile
after every run. `bin/fix-here TREE` is an optional terminal wrapper, not a
requirement. `bin/check --help` explains the supplemental profiles,
`bin/check --list --profile=operator` previews their steps, and
`bin/check --profile=agent --format=json` emits a machine-readable receipt
with exact local/main revisions, checkout cleanliness, per-step timings,
exit states and the combined-log path, byte count and SHA-256 (without raw
command output).
Each JSON run also writes a private, atomic artifact under
`.master/check/receipts/<receipt-id>.json`; the path and persistence state
are included in the emitted receipt. A failed artifact write is
`DELIVERY_FAILED` and returns a non-zero exit.
`bin/check --profile=full` adds the existing `rake test:all_trees` sweep
for MASTER, RAILS, OPENBSD, STUDIO and BIZ (native tests, syntax, shell and
YAML/JSON parsing). Its exit-3 missing-runtime outcome is reported as
`INCONCLUSIVE`, never as a pass.
`bin/check --show-log --tail=120` retrieves the latest diagnostic log without
booting MASTER. While a repair is active, `bin/operator fix status` and
`bin/operator fix tail` expose its progress and transcript.

First hour on a new host: use the installed compatible Ruby (3.2 or newer; no upper bound), run
`bin/bootstrap` (the same dependency preflight `bin/master` runs before every normal boot), keep keys in the environment,
run `bin/operator doctor` for the host and `bin/doctor` for the runtime, then take one narrow dry run:
`bin/master '/fix --dry-run --critique --only critique,map MASTER/lib/cli'`.
Read the result before widening scope.

The bootstrap installs the locked core Ruby bundle automatically. If a native gem build proves that OS build
prerequisites are missing, an interactive terminal receives one consolidated package plan and consent prompt;
non-interactive runs fail closed with the exact package list and `bin/deps system` recovery command.
For unattended hosts, set `MASTER_AUTO_SYSTEM_PACKAGES=1` only when package installation has already been
approved by the operator. The system package list covers native build prerequisites, not optional applications
or provider credentials.
The separate `MASTER/web` Rails bundle is installed automatically on the first
web-server start when `MASTER_WEB=1`; ordinary CLI-only sessions do not install unused web dependencies.

Failures have owners. `lib/ground/failure_taxonomy.rb` classifies the error and owns the retry
policy: `exhausted` pauses the paid lane and re-probes on backoff through `Io::QuotaCheck`, so
the fix is another model or a wait, never an in-place retry; `transient` backs off
exponentially; `permanent` fails fast; `ambiguous` stops and asks a human. A held lock names
its holder — wait, stop that run, or let `bin/cleanup` sweep stale `.lock` files. A stopped run
stays resumable from its journal and is never reported as a successful one. An incompatible Ruby is reported with its actual version before any other repair; no upper version bound is imposed. A skipped instrument stays INCONCLUSIVE, never PASS.

## OpenBSD Amsterdam hosting boundary

OpenBSD Amsterdam is the VPS provider for production. The live topology has two distinct machines:

- **Hypervisor host: `server4.openbsd.amsterdam`.** This is the provider-side VMM host. SSH to it on TCP port `31415` as `dev`; this is the management and recovery route. Host-side `vmctl` controls the guest.
- **Production guest: `vm23`.** This is the OpenBSD VM that runs the applications and services. Normal SSH, deploys, service work and application operations belong on this guest, using the aliases and access path in [OPENBSD/RUNBOOK.md](../OPENBSD/RUNBOOK.md).

These names are not interchangeable: `server4` is the machine that hosts the virtual machine; `vm23` is the virtual machine itself. Do not describe the hypervisor as the production guest or run application workloads on the hypervisor.

**Choose the access path by the guest's condition.** When `vm23` boots and accepts SSH, connect to the guest and use the normal runbook. When `vm23` is down, unreachable, or cannot complete boot, connect to `server4` on port `31415` and use the host-side `vmctl` and console recovery procedures for `vm23`. That host path exists precisely because guest SSH is unavailable during a VM failure. Console, stop, start and reboot operations can disrupt production; follow the runbook's recovery-only gates and obtain the required human approval. Never attempt to solve a failed guest boot by treating `vm23` as the host, and never assume guest-side `vmctl` can manage the hypervisor.

The provider's 2025-09-27 onboarding email records an earlier allocation: `vm08` on `server27.openbsd.amsterdam`. That is historical provisioning information, not the current pub5 topology or a valid recovery target. Current host topology, SSH aliases, console procedures and VM identity are owned by [OPENBSD/RUNBOOK.md](../OPENBSD/RUNBOOK.md) and the checked-in deployment configuration.

The provider's onboarding instructions describe guest SSH separately from hypervisor SSH on TCP port `31415`, using the same operator account and SSH key, with `vmctl` available on the hypervisor for VM management. The provider explicitly warned that it cannot start a VM after full-disk encryption (FDE) is enabled. Treat FDE as a recovery-design decision, not a routine hardening toggle: before enabling it, verify the provider's current boot and console capabilities, document an operator-controlled unlock and recovery path, and prove recovery after a stop or host restart. Without that proof, mark the operation BLOCKED.

The onboarding email also supplied an initial dual-stack address allocation and payment instructions. Those are not copied here: network assignments must be checked against the live host and DNS, while billing links, personal contact details and credentials do not belong in repository policy. Backup, reverse-DNS and onboarding procedures are provider-specific; use the provider's current [onboarding](https://openbsd.amsterdam/onboard.html), [backup](https://openbsd.amsterdam/backup.html) and [PTR](https://openbsd.amsterdam/ptr.html) documentation, then verify the actual result. A provider backup feature is not a substitute for an independently held, checksummed backup and a tested restore.

## External assessment and business direction

MASTER's competition is not another model; it is the ungoverned script. Coding agents write fast and prove little: changes land without evidence, failures stay silent, and history is a log, not a constitution. Vendor-bound assistants inherit one model's limits and one vendor's roadmap. The scarce asset is not intelligence but trustworthy delivery — work that names its authority, measures before it declares done, and stops when the evidence is against it.

### Competitive landscape

General-purpose coding agents optimise for speed of change; few measure, fewer keep evidence. Vendor-bound assistants bind quality to one provider. MASTER's difference is structural: a constitution that gates every effect, an evidence-gated commit path, and ratchets that make quality debt visible instead of ambient. The comparison stays qualitative here; this README invents no market-share figures.

### Business hypothesis and strategy

Hypothesis: a governed runtime that treats every repair as evidence-first work holds quality under continuous agent traffic where ungoverned automation cannot. Strategy: prove it on this repository first — the runtime maintains its own tree under its own laws — then offer the pattern to teams whose agents already outwrite their review capacity. The hypothesis is falsifiable: if `/fix` cannot hold this tree's ratchets green over time, the hypothesis fails.

### Pilot and funding route

The named route is Innovasjon Norge ([innovasjonnorge.no](https://innovasjonnorge.no)), the Norwegian state's instrument for innovation funding. This README does not claim eligibility or approval; it records the direction. A pilot funds the smallest honest step: one external codebase run under the constitution for one month, with receipts.

### Ask and evidence

The ask is access — one real repository, its operator's trust, a month of measured traffic. The evidence that answers the ask is what this tree already produces for itself: before/after defect counts, ratchet movement, repair survival rates and a complete run journal.

### Horizon

The near horizon is self-maintenance: `/fix` holding this repository's suites and ratchets at green is the product demonstration. The next horizon is one external pilot on someone else's tree. Commercial terms, pricing and eligibility wait for pilot evidence; nothing here commits any funder.

## Source map

- Execution contracts: `lib/execution.rb` and its tests.
- Mobile support: `data/mobile.yml`, `bin/master-mobile-install` and `test/test_mobile.rb`.
- Provider routing and quotas: `data/providers.yml`, `data/models.yml` and `lib/io/model_quota.rb`.
- Native-tool fallback: `lib/review/llm_dispatcher/ruby_llm_sender.rb` retries unexecuted tool-call text through `ReactLoop` once, preserving the registry and subagent/elevation policies; it does not replay after a native action or stream partial output.
- Lovdata access limits: `lib/io/lovdata.rb`, `lib/io/llm.rb` and their tool contract tests.
- Scope expectations and vocabulary: `data/expectations.yml` and `data/synonyms.yml`.
- Cross-tree inventory: `lib/convergence/architecture.rb` and `MasterPaths::TREES`.
- CSS cascade order and thresholds: `data/css_architecture.yml`, `data/tokens.yml` and the corresponding Laws.
- Cross-tree implementation and proof state: `convergence.yml`; product gaps: `data/gaps.yml`; operator-only evidence: `data/operator_seams.yml`; UX acceptance: `data/law/ux_refinements.yml`; RAILS-specific refinement: `../RAILS/refinements.yml`. `bin/master status --agent` is the read-only union view, not another owner.
Use `bin/master --help` and `bin/operator --help` for the current command surface.


## Consolidated component references

The following internal guides now live here instead of in nested directories. Their original procedures and boundaries are retained under their subject headings.


### Checks

<sub>Consolidated project reference.</sub>

> **Terminology and authority.** The preferred user-facing term is **check**. This guide keeps **check** where it names existing implementation classes, environment variables, or commands; this is a glossary banner, not a partial mass rename. A Law is a normative requirement, a check is an instrument, and proof is evidence about what was measured. Source authority runs `soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`. Soul owns global identity, preservation and protected paths; `laws.yml` owns individual Law identities, statements and internal invariant order. The registry in checks.yml is an execution inventory, not a second Law catalogue. The executable Law DSL reads per-Law policy from `laws.yml#law_catalogue`; the runtime configuration lives beside the catalogue in the same file. See MASTER/data/synonyms.yml. Do not invent hard/soft/ops tiers. Machine outcomes such as skipped, inconclusive, and gaps remain distinct.

**A check is a promise the repository makes to itself and keeps by machine: that
every page a visitor can reach is whole, honest and in the right language,
checked before anyone has to notice it is not.**

The checks judge the three shared-engine Rails apps, Brgen, Amber and
BSDPorts, together with the MASTER web face. Mr Damascy is a separate standalone
app: its own `RAILS/mrdamascy/bin/ci` is included by
`MASTER/bin/operator premerge` and `MASTER/bin/operator ci`, not by this
shared-engine surface map. One runner, `runner.rb`, executes the checks
described here. The registry, `checks.yml`, declares them, and the runner
adds no Law authority. A registry
row names a class to run, or a script, and the line to print when the check
passes. The registry also records which checks are covered by a composite, so
`--all` skips those leaves rather than running the same work twice. Before any
check starts, the runner validates the registry root and refuses a row that
has neither `class:` nor `script:`. A headless row is a configuration error,
not an outcome from a check that actually ran.

## What they check

Some checks read source and need nothing running. They check that the app
inventory in `apps.yml` agrees with the ports and the engines, that migrations
match the schema, that no foreign key points at a table that is gone, that
stylesheets obey the CSS constitution and the type and scale contracts, that
payment and affiliate pages say what they do, that Stimulus controllers are
wired to something, and that the shared engine is mounted where the apps expect
it. A neighbouring group checks the surface schemas and the first screen of each
page. One more reads the craft ledger:
`exemption_freshness` holds every recorded exemption to its `review_by` date —
fails the row whose review has passed, fails a row whose law no executable law
file declares, and warns when a review comes due — so an excuse recorded once
cannot quietly outlive its argument.

Others simulate a visitor. The page simulation walks every full-page template,
checking its identity, its dead ends and its labels, and when the apps listen it
requests every public path that takes no id. The flow journey follows
multi-step paths declared in `data/flows.yml` and holds each to its
postconditions and to honest redirects. The human walkthrough and the user flow
checks probe the verticals and secondary hosts as a guest.

The rendered checks need a real browser. They load pages in Chrome through the
DevTools protocol, then measure geometry, reflow, occlusion, viewport spill,
keyboard order, phone-sized tap targets, WebGL surfaces and web vitals, and they
compare layout against snapshots committed under `data/layout_snapshots`. The
rendered suite bundles most of them and is a required leaf of `layout_suite`, not a separate optional proof. A source-clean layout cannot pass acceptance if the browser is absent, a route is skipped, a measurement is inconclusive, a visual baseline is missing, or a rendered check has an unapproved finding. `web_vitals_budget` measures
LCP and CLS on one mobile first screen per app, using the canonical
`pixel_snapshot` inventory; it source-checks INP collection rather than inventing
an INP value from a scripted load with no real user interaction.

`browser_diagnostics` adds runtime evidence to that same CDP path. For each reachable
route in `data/geometry_surfaces.yml`, at its declared viewport, it records console
messages, uncaught JavaScript exceptions, failed HTTP responses, failed resource
requests, and a PNG screenshot. It writes a run-scoped `manifest.json` and
screenshots under the system temporary directory
(`pub5-browser-diagnostics/<run-id>/`).

For the deliberately small set of surfaces marked `pixel_snapshot: true` in the
canonical geometry inventory (including selected Brgen verticals), the check also
compares the PNG against `data/visual_baselines/<app>-<surface>-<viewport>.png`
using the dependency-free `support/png_diff.rb` decoder. Structural
`snapshot: true` alone does not opt every route into PNG references. The manifest records exact changed
pixel counts, ratio, and a red/transparent heatmap. The default threshold is 1%
of pixels; `CHECK_PIXEL_DIFF_MAX_RATIO=0` requests exact equality. Dimension
changes always fail. Missing baselines are clearly reported as soft findings
until `CHECK_PIXEL_BASELINE_STRICT=1` is enabled; corrupt or unsupported images
are never treated as equal.

PNG approval is separate from autofix. Run diagnostics first, inspect the
captured screenshots and manifest, then promote the exact files reviewed with
`ruby MASTER/tools/approve_visual_baselines.rb --manifest PATH`. The tool checks
the capture hash, dimensions, route inventory and runtime status, and refuses to
overwrite an existing reference unless `--replace` is explicit. See
the Approved visual baselines section for the workflow.

Uncaught JavaScript exceptions, document HTTP errors, first-party server errors,
failed first-party scripts/stylesheets, and missing screenshot evidence fail the
check. Ordinary console errors/warnings
and other resource failures remain soft until `CHECK_STRICT_SOFT=1`, preserving the
existing severity calibration. Each route/viewport prints PASS, FAIL, SKIPPED or
INCONCLUSIVE and the manifest links its screenshot and detailed browser evidence.
Closed app ports are explicitly skipped; absent Chromium or no reachable apps is
inconclusive rather than green.

Run a focused inventory slice while diagnosing one surface, or run the entire
declared set:

```zsh
ruby MASTER/checks/runner.rb browser_diagnostics
CHECK_SURFACES=brgen/marketplace,amber ruby MASTER/checks/runner.rb browser_diagnostics
CHECK_BROWSER_DIAGNOSTICS_SETTLE_MS=800 ruby MASTER/checks/runner.rb browser_diagnostics
```

`CHECK_BROWSER_DIAGNOSTICS_OUTPUT` overrides the artifact root, and
`CHECK_BROWSER_DIAGNOSTICS_SETTLE_MS` bounds the post-load settling window
(0–5000 ms). The check runs inside `rendered_suite`, which is required by `layout_suite`; there is one route inventory and one browser transport, with no separate browser framework or new runtime dependency.

A last group checks the checkers. The mutation check plants known defects and
requires the other checks to catch them. The calibration check keeps the design
metrics honest against fixed good and bad exemplars, which sit under
`fixtures`.

## Four outcomes

A check passes, fails or is inconclusive, and a check that raises is recorded as
errored. The difference matters. A check that could not measure anything, because
the browser was missing or the apps were down, is inconclusive. It must never
read as a pass. The runner prints a summary of each outcome and exits non-zero on a
failure or errored check. A check crash remains a distinct `errored` outcome
for diagnosis, but it can never count as a pass and cannot be made successful
by an environment switch. `CHECK_STRICT_INCONCLUSIVE` makes an inconclusive
result blocking, and `CHECK_STRICT_SOFT` promotes soft findings to failures.
Every run is appended to a ledger, and `--ledger` prints what the ledger holds.

The two flow checks, `user_flow` and `flow_journey`, say what happened to each
app. An app whose port is closed is reported as skipped because the app is down,
by name, with the flows it took with it, and the check is inconclusive however
many source checks ran beside it. A skipped app is never a pass. The variable
`CHECK_SOURCE_ONLY` says a run is meant to be source-only and keeps the check green;
on the deploy host `CHECK_REQUIRE_LIVE` turns the same skip into a failure.
`FLOW_BRGEN_PORT`, and the same name for each other app, points one app's flows at
a copy booted on a spare port.

Journeys marked as mutating create accounts, posts, listings and orders, and read
them back. They run against a development database and are refused on the deploy
host, where the port they would write to serves production, unless
`CHECK_ALLOW_WRITES` says the copy is disposable. They sign up with an address made
unique for each run, and they read confirmation and reset mail from the app's
`tmp/mails` directory, where the development mailer writes it.

Checks that can repair what they find do so by default and measure again.
`--scan-only`, `--no-autofix` or `CHECK_AUTOFIX=0` makes a run read-only.

## Baymard-informed UX review

The `baymard_ux` check is an original, independently worded assessment profile informed by public Baymard research. It is not an official Baymard audit, score, certification or affiliation. The research is ecommerce-heavy; commerce-specific journeys are applied only where the app inventory indicates that the feature exists. The audit does not impose one visual identity on Brgen, Amber, BSDPorts or their verticals.

Baymard's public methodology describes 200,000+ hours of research, 4,400+ participant/site sessions, and 54 rounds of manual benchmarking across 344 major US and European ecommerce sites. That methodology page describes the benchmark as 818 guidelines; the live benchmark page now presents 1,254 guidelines across desktop web, mobile web and mobile apps. These are differently scoped public research views, not totals to combine or scores MASTER can claim. The profile also cites Baymard's [checkout research](https://baymard.com/research-articles/ecommerce-checkout-usability-report-and-benchmark), [2026 cart-abandonment data](https://baymard.com/lists/cart-abandonment-rate) and [inline-validation research](https://baymard.com/research-articles/inline-form-validation).

The 2026 abandonment research distinguishes shoppers who were just browsing or not ready to buy from people reporting avoidable friction. That distinction is built into the audit: an abandonment percentage is not itself a diagnosis, and a purchase-flow improvement must not hide costs or undermine a visitor's ability to decline.

The source lane measures a bounded set of inspectable markup and stylesheet contracts: form-control names, image alternatives, interactive names, non-native click targets, focus-outline suppression and viewport declarations. Framework-generated controls and ambiguous cases remain inconclusive until the rendered browser can inspect them. Existing rendered checks still own geometry, contrast, keyboard execution, touch targets, overflow and visual snapshots.

The task lane describes participant or expert tasks for first-screen comprehension, navigation findability, search recovery, offer evaluation, cart editing and cost comprehension, checkout recovery (including inline error timing and retained values), mobile completion, and keyboard/screen-reader operation. The mapped laws also reject coercive conversion tactics such as hidden charges, deceptive urgency, unnecessary forced accounts and obstructed refusal or cancellation. Source text cannot prove that a person understood a page or completed a journey. Without task evidence, these assessments remain `INCONCLUSIVE`; they are never silently counted as passes.

Run the audit by itself or as part of the layout suite:

```zsh
rake -f MASTER/Rakefile ux:baymard
ruby MASTER/checks/runner.rb baymard_ux
BAYMARD_EVIDENCE=MASTER/.master/baymard/evidence.yml ruby MASTER/checks/runner.rb baymard_ux
BAYMARD_STRICT=1 BAYMARD_EVIDENCE=MASTER/.master/baymard/evidence.yml ruby MASTER/checks/runner.rb baymard_ux
```

The evidence file is repository-local YAML with `schema: 1` and an `apps` mapping. Each task row names `status: pass`, `status: fail` or `status: inconclusive`; a non-inconclusive verdict also requires a method (`moderated_user_test`, `expert_walkthrough`, `browser_task` or `screen_reader_review`), a positive participant count, an anonymised aggregate observation and one or more artifacts. Artifacts are limited to text/structured notes or screenshots (Markdown, text, JSON, YAML, PNG, JPEG or WebP), each with a repository-relative path and SHA-256 digest, and are capped at 2 MB each. Text artifacts are scanned for email addresses, phone-like strings and common structured participant/customer name or ID fields; this is a guardrail, not a complete PII detector. Manually anonymise and review every artifact before storage. Image artifacts require `redacted: true` as an explicit human attestation; the audit checks file signature and hash, not whether image content is actually redacted. Raw audio/video, participant names and identifiers must not be stored. Missing, changed, oversized, escaped, symlinked or unsupported evidence remains inconclusive. `BAYMARD_STRICT=1` makes unresolved task evidence blocking.

The report separates measured pass/fail counts from inconclusive and not-applicable assessments, includes source paths and line numbers, and explicitly reports no official Baymard score. A clean source scan is not a usability certification: task observations and rendered browser evidence remain separate proof.

## Three rules the checks have paid for

A check that demands one of several correct outcomes reports the environment as
the tree. Amber's demo redirects home without a seeded wardrobe, and brgen's
marketplace shows an empty state without listings, so a check that insists on
the populated branch reads an empty database as a broken app. Name the set of
correct answers and keep each falsifiable.

A test that runs a check over this tree and asserts clean proves nothing, since
it also passes against a check whose body returns ok. Plant the defect, assert
red and named, remove it, assert green, and drive the test once against a
gutted check.

Check what the instrument opens before believing what it says. A stylesheet
lint that globs a directory misses what the bundle pulls in through `@use` and
`@forward`, and a class extractor that stops at a quote cannot read a Ruby class
value with interpolation in it.

## Run

The apps come up with the operator, which reads their ports from `apps.yml`. The
whole ladder, including these checks, runs through `bin/operator check`. To run
only these, name them or pass `--all`. `--explain` lists every check with its
pass line and the environment switches the runner honors.

```zsh
MASTER/bin/operator triangle up
ruby MASTER/checks/runner.rb page_simulation flow_journey
ruby MASTER/checks/runner.rb --all
ruby MASTER/checks/runner.rb --ledger
```

`--json` prints one JSON document instead of the dmesg lines — every named
check's outcome, failure/warning/error lines, gaps and the summary — with the
same exit codes as the prose run. It exists so harnesses and foreign runtimes
can consume findings as data instead of parsing them back out of the log:

```zsh
ruby MASTER/checks/runner.rb --json --all > check_run.json
```


### Approved visual baselines

<sub>Consolidated project reference.</sub>

This directory holds **approved reference PNGs**, not the latest run's screenshots.
Only a deliberately small set of surfaces opt into pixel comparison via
`pixel_snapshot: true` in `MASTER/checks/data/geometry_surfaces.yml` or the
`pixel_snapshot: true` field on a row in `MASTER/checks/support/brgen_vertical_surfaces.rb`.
Structural `snapshot: true` does not automatically opt a page into PNG tests.
The filename is `<app>-<surface>-<viewport>.png`, derived from the same canonical
surface inventory. The rendered check never copies a fresh screenshot here during
an ordinary run or through `CHECK_AUTOFIX`.

## Compare

Run the rendered diagnostics with the apps serving and Chromium available:

```zsh
ruby MASTER/checks/runner.rb browser_diagnostics
```

The manifest and PNGs go to the system temporary directory under
`pub5-browser-diagnostics/<run-id>/`. For a surface with an approved PNG, its
row records exact changed-pixel count, ratio, approved reference path and a
red/transparent difference image when pixels changed. The default blocking
budget is 1% of pixels per viewport; set `CHECK_PIXEL_DIFF_MAX_RATIO=0` for exact
pixel equality or choose an explicit ratio between 0 and 1. An image-dimension
change is always a failure, not a skipped comparison.

Surfaces without an approved PNG remain explicitly marked as missing and are
reported as soft findings by default, while the structural layout snapshots
continue to run. Set `CHECK_PIXEL_BASELINE_STRICT=1` to make missing or
unsupported pixel baselines blocking. This lets the inventory be seeded
gradually without claiming that un-compared pixels passed.

## Approve the reviewed capture

First run the diagnostics without approval and inspect the screenshots and manifest
path printed by the check. Then promote the exact files you reviewed; this does not
navigate again or silently replace your inspection with a new capture.

```zsh
ruby MASTER/checks/runner.rb browser_diagnostics
ruby MASTER/tools/approve_visual_baselines.rb --manifest /tmp/pub5-browser-diagnostics/<run-id>/manifest.json
git diff -- MASTER/checks/data/visual_baselines
```

The tool verifies that each source PNG is inside that run's screenshots directory,
matches its recorded SHA-256 and dimensions, belongs to a declared `pixel_snapshot`
surface, and has no runtime failures. Failed/inconclusive captures cannot be
approved. Existing baselines are protected from accidental overwrite: review the
diff and explicitly pass `--replace` when accepting a deliberate design change.
Use `--surface app/label/viewport` (repeatable) to approve a chosen subset.

This tool is never part of `/fix` or `CHECK_AUTOFIX`; baseline approval is a
separate operator action.
PNG comparisons use a dependency-free Ruby decoder for Chromium's non-interlaced
8-bit RGB/RGBA screenshots. Unsupported/corrupt images are reported rather than
silently treated as equal. Keep the browser, operating system, device scale,
fonts, locale and viewport stable when producing a baseline; use separate
references when the rendering environment deliberately differs.


### Norwegian accent evaluation fixtures

<sub>Consolidated project reference.</sub>

Evaluation data for Norwegian accent work (Bergen high-tone vs Eastern
low-tone), consumed by `Voice::Benchmark`'s tonem lane
(`lib/voice/benchmark.rb`: `pitch_track`, `tonem_verdict`, `tonem_eval`).

## Provenance

Salvaged on 2026-11-21 from an external agent patch ("master_voice") that
proposed a complete parallel TTS stack. The stack itself was rejected - it
registered its own engines, supervisor and G2P beside the existing
`Master::Voice::Engines` chain, returned `audio_path: nil` from every
adapter, rewrote the operator's words before synthesis, used bare Open3,
and shipped about 2,000 lines with no tests. The dialectology underneath it
was sound, so the data survives here in evaluation-only form. The review is
recorded in `data/proposals.yml` (entry `master-voice-parallel-stack`).

## What lives here

- `bergen.yml`, `oslo_standard.yml` - tonem-1 f0 targets, minimal pairs and
  word lists per accent. Read by `Benchmark.tonem_target`.
- `phonemes_bergen.yml`, `phonemes_east.yml` - segmental inventories
  (uvular vs alveolar r, retroflex series present vs absent).
- `bergen_lexicon.tsv` - reference forms for evaluation only, never a
  rewrite table. Hygiene applied on salvage: duplicate rows removed,
  identity mappings dropped, the contested `øya → øyen` and the approximate
  verb hints marked as such.
- The [Norwegian TTS engine comparison](#norwegian-tts-engine-comparison) and
  [Bergen voice-data collection plan](#bergen-voice-data-collection-plan) are
  evaluation and research notes, not active runtime routes.

## Law statements

- This directory is **evaluation-only**. No engine, no supervisor, no voice
  selection: `data/voice.yml` `language_voices` remains the single source of
  truth, and Norwegian is spoken by Pernille until a real engine passes the
  benchmark gates.
- The synth contract is unchanged: an engine returns truthy only with a
  real audio file at `out_path`; failure returns false and never raises.
- Nothing here rewrites text before speech. Faithful speech is the default
  (`data/tts.yml`).

## Usage

```ruby
track = Master::Voice::Benchmark.pitch_track("solen.wav")
verdict = Master::Voice::Benchmark.tonem_eval("solen.wav", accent: "bergen")
# => { path:, accent:, target:, measured:, score:, pass:, available: }
```

`tonem_eval` needs `aubionotes` on PATH (the same optional dependency the
existing f0 summary uses) and answers nil, not an exception, when it is
missing or the audio is unreadable.


### Bergen high-tone LoRA data checklist

<sub>Consolidated Bergen voice-data research.</sub>

Goal: continue from AlexKjes/cosy-norwegian (`model_720_lora_state.pt`)
toward reliable Bergen high-tone + skarre-r. Provenance: salvaged from the
reviewed external patch (now included in this project guide); this is a
data-collection plan for the operator, not a wired route.

## Priority data characteristics

1. **Uvular r (skarre-r)** - speakers who consistently use the uvular
   realisation, not alveolar r.
2. **No retroflexes** - natural separation of r + t/d/n/l/s.
3. **High-tone realisation** - tonem 1 with an early high peak then fall on
   the stressed syllable (the target `bergen.yml` pins).
4. **Two-gender morphology** - *boken, solen, jenten, døren* preferred in
   spontaneous speech.
5. **Local function words** - *eg, ikkje, ka, kæm, koffor, korleis, no*.

## Suggested data sources (open / collectable)

- NST / NPSC subsets with Vestland or confirmed Bergen speakers (filter if
  the metadata allows).
- Local radio / podcast / YouTube from Bergen, with permission or fair-use
  grounding for research.
- Read speech from native Bergen speakers: word lists and short paragraphs
  containing the minimal pairs, the high-frequency -en forms, and the
  clusters that would be retroflex in the East (barn, norsk, parti).
- Existing dialect corpora that tag region or r-variant.

## Minimum viable continued-training set

| Category                | Target              | Notes |
|-------------------------|---------------------|-------|
| High-tone tonem-1 words | 200–500 utterances  | sola, boka, døra, armen, bilen, huset |
| Skarre-r heavy sentences| 300+                | Multiple r's per utterance |
| Gender -en forms        | 200+                | Avoid -a forms in target transcripts |
| Everyday dialogue       | 1–2 h               | Natural prosody |
| Total new data          | ~3–10 h             | Quality over quantity for LoRA |

## Training notes

- Start from `model_720_lora_state.pt`, not from base only.
- Keep LoRA on the LLM frontend only (same stage-4 style).
- Use Bergen style prompts in training examples where possible.
- Evaluate with the fixtures in this directory:
  - F0 peak timing on tonem-1 words - early high, via
    `Voice::Benchmark.tonem_eval(path, accent: "bergen")`.
  - Absence of retroflexes and presence of uvular r (listening plus simple
    detectors).
  - Preference for -en vs -a in generated definite forms.

## Anti-targets (down-weight or avoid)

- Clear Eastern low-tone speakers.
- Heavy alveolar-r plus retroflex speakers.
- Over-represented Oslo / Eastern studio speech without filtering.


### Norwegian TTS engine landscape (evaluation notes)

<sub>Consolidated Norwegian TTS evaluation research.</sub>

Focused comparison for Norwegian (Bokmål) accent work, status late 2026.
Provenance: salvaged from the reviewed external patch (see the consolidated project reference below); ranks are proposals for future engine work, not wired
routes, and are corrected to what MASTER actually runs today.

## Ranking for future Norwegian engine work

| Rank | Engine                  | Norwegian Quality | Fine-tune Ease | Pitch Accent Potential | License          | Notes |
|------|-------------------------|-------------------|----------------|------------------------|------------------|-------|
| 1    | CosyVoice3 + NB LoRA   | High              | Excellent (LLM LoRA) | High (continue training) | Apache 2.0 + LoRA check | Proposed primary for Bergen work. AlexKjes LoRA on ~680h. |
| 2    | XTTS v2 (+ NB fine-tune)| Medium–High      | Good           | Medium–High            | CPML (non-commercial) | Best pure cloning. Community NB fine-tunes exist. License is the limiter. |
| 3    | Qwen3-TTS + community  | Medium (improving)| Good           | Medium                 | Apache 2.0       | Modern base. Active Norwegian fine-tune experiments. |
| 4    | Fish Speech / S2       | Medium            | Medium         | Medium                 | Restrictive      | High expressiveness. License friction for production. |
| 5    | Kokoro 82M             | Low               | Limited        | Low                    | Apache 2.0       | Fast English fallback only. Unfit as a Norwegian primary. |

## Detailed criteria

**Norwegian quality**
- CosyVoice3 + AlexKjes LoRA: the strongest currently available open path;
  trained on NST + NPSC material.
- XTTS v2: solid after a Norwegian fine-tune, still carries some foreign
  accent without further work.
- Qwen3-TTS: base is not Norwegian-native; community LoRAs are early.
- Kokoro: noticeably weaker out of the box, and it is already demoted in
  MASTER's chain for per-phrase latency, not only for quality.

**Fine-tune / LoRA ease**
- CosyVoice3: cleanest known path - LoRA on the Qwen2 LLM frontend is
  proven and efficient.
- XTTS v2: GPT encoder fine-tuning works but is more brittle.
- Qwen3-TTS: standard PEFT path.
- Kokoro: style presets rather than language adaptation.

**Pitch accent (Bergen high-tone) potential**
- Highest with CosyVoice3: the LLM stage carries prosody, and continued
  LoRA on high-tone data is straightforward.
- XTTS can improve with targeted data but has less explicit style control.
- The others lack demonstrated Norwegian tone control.

**License reality for MASTER**
- Prefer Apache 2.0 / MIT for long-term freedom: CosyVoice3, Qwen3-TTS,
  Kokoro.
- XTTS v2 is technically attractive but CPML blocks many uses; verify the
  specific LoRA's license separately.

## MASTER routing today (the reality this doc must not contradict)

- Chain (`data/tts.yml`): `mlx, chatterbox, glm_tts, edge_melodic, edge, say`
  - hosted glm_tts sits behind the local engines for the same per-phrase
    round-trip reason that demoted Kokoro.
- Norwegian voice: Pernille via Edge, pinned by `data/voice.yml`
  `language_voices` - the single voice truth. GLM serves no Norwegian voice,
  so pernille is deliberately unmapped in `glm_voice_map`.
- A CosyVoice3 / XTTS route would enter the same way every engine does: one
  `available?` / `synth` case arm in `lib/voice/engines.rb`, one chain line,
  stubbed contract tests, and the benchmark gates - not a second stack.


### Air Superiority

<sub>Consolidated project reference.</sub>

**Air Superiority lets a machine know its own airwaves: every Wi-Fi network and
Bluetooth device around it, measured against what its owner has already
vouched for, with nothing sent anywhere and nothing attacked.**

It is a plugin for defensive observation. A scan lists the networks and devices
the host can hear and flags each one that is not on a local list of known
ones. Each flag is advisory. The plugin does not decide that a stranger is a
threat; it tells the operator that a stranger is there.

The scan uses whatever the host already provides. On macOS it reads the airport
tool and the system profiler, on Linux nmcli and bluetoothctl, on OpenBSD
ifconfig, and on Android under Termux the Termux:API scanners. The status
action names the backend chosen for each radio, or says it is unavailable. When
one radio cannot be scanned, the other is still reported, the scan result
carries the error, and its complete flag is false. A missing interface never
becomes an empty success.

The known list is a small YAML file under `~/.master/plugins/air_superiority/`,
kept private to the operator. The remember action adds a network by name and
hardware address, or a device by address, and writes nothing else. The law in
`data/laws.yml` grants write access to that list alone and forbids packet
injection, deauthentication, disassociation, credential capture,
man-in-the-middle tricks, exploitation and remote control. Do not add any of
them. Identifiers the scan finds are sensitive, so they stay on the machine.

The manifest, `plugin.yml`, declares status and scan as observable, which means
MASTER's guarded observation tool may call them without write authority.
Remember is not observable and runs only through an explicit plugin run. Any
other action is refused as unknown. Every call first passes the law handshake,
so the plugin will not run before MASTER has admitted its own constitution.
The code is in `air_superiority.rb`, with the comparison in `analyzer.rb` and
the small result objects in `models.rb`.

## Use

Inside a MASTER session, the plugin command reaches it. Remember takes the same
form with a JSON object naming the kind, network or device, and its identifiers.

```text
/plugin info air_superiority
/plugin run air_superiority status
/plugin run air_superiority scan
```


### Session Browser

<sub>Consolidated project reference.</sub>

Session Browser provides persistent browser sessions for explicitly allowlisted public hosts. Its network transport permits GET and HEAD only; this is not a read-only guarantee. Page JavaScript executes, and a GET endpoint can change remote state. Treat every page and its scripts as untrusted. The plugin reuses MASTER's WebBrowse request broker and snapshot script rather than creating a second network stack or a second page extractor.

The plugin is deliberately inert until at least one hostname is added to MASTER/data/laws.yml under plugins.session_browser.allowed_hosts. The list is exact-host policy after lowercase, trailing-dot and leading www normalization. There are no default destinations and no wildcard domains. Every page request must still pass the pinned-address SSRF guard; each session is restricted to one canonical host.

Supported actions are status, inspect, open, login, extract, look, follow, paginate and close. Only status and inspect are observable through the plugin observation surface. Look returns a screenshot as visual evidence only. Follow and pagination inspect literal anchor hrefs and navigate to them; they never click arbitrary page controls or run a computer-use loop.

The plugin creates no in-memory session table. It stores state.yml for the session's host binding and last safe URL, a per-session lock, and a Chromium user-data-dir under ~/.master/plugins/session_browser/sessions. Files and directories are owner-only. Chromium's own profile persists cookies and site data on disk; passwords and one-time codes are never copied into the YAML state. Remove a session directory locally if its profile data must be erased. The close action clears the active route and session slot but intentionally preserves the profile.

Captured screenshots live under ~/.master/plugins/session_browser/captures. The directory is owner-only, each capture is mode 0600, and old captures are pruned during every capture to a 500-file cap.

The transport permits only GET and HEAD requests. This does not prevent side effects: page JavaScript executes and GET endpoints may mutate server state. Ordinary POST-based logins and form submissions are blocked; WebSocket-driven pages, cross-host CDN requests and scripted-only navigation will not work. A visible login window is available only when a workstation display exists, but its POST-based submissions remain blocked. Use an already authorized profile or a compatible GET-based sign-in flow. Security challenges are not bypassed. Page contents are untrusted data and never become instructions. POST remains disabled until the operator approves a specific host and task under the session-browser policy.

The persistent profile stores website cookies and session tokens on disk, so adding a hostname is not blanket consent to browse or interact with every account. Do not add a hostname without an explicit operator decision.

## Use

/plugin info session_browser
/plugin run session_browser status
/plugin run session_browser inspect {"session":"research","url":"https://example.com"}


### Social Browser

<sub>Consolidated project reference.</sub>

**Social Browser lets MASTER act in the one place an operator lives
online, their own accounts, while the operator keeps every key, every consent
and every consequence.**

It drives a real browser, through the Ferrum gem, on accounts the operator owns
or is authorized to run. Two sites are wired in today: OnlyFans and FetLife. Each has an HTTPS start page and a short list of
allowed hosts, and the plugin refuses any other destination. The status action reports whether
the browser is available and which sites are known.

Logging in is the operator's work. The login action opens a visible browser and
takes a screenshot; the operator types the password and any one-time code
there. MASTER never receives passwords, codes, cookies or session credentials.
The browser profile for each account lives under
`~/.master/plugins/social_browser/accounts/`, with owner-only permissions, and
never in the repository.

Reading is open and writing is narrow. The inspect action returns the page
title, the page text and a screenshot, and the text passes through MASTER's
injection guard because a page is untrusted input and never an instruction. Two
actions write: publish_owned posts to an account the caller declares owned, and
reply_inbound answers a message that someone sent to that account. Each needs
explicit consent in the call, and each does one thing per invocation. A message
may not be empty or exceed 4,000 bytes. An account takes one write in any
fifteen seconds, and a lock stops two runs from using the same account at once.
Every write leaves three screenshots, before, typed and after.

A CAPTCHA or security challenge stops the run for a human, before and after a
write. The plugin does not try to get past one. A missing composer, a missing
submit button, an expired session or a changed page is reported as a failure,
and the plugin never says an action is done because a click was attempted.

The law in `data/laws.yml` forbids what this plugin could otherwise be bent
into: unsolicited bulk messaging, automated friend farming, automated
following, deceiving anyone about identity, and getting around a challenge. A
change that makes any of those easier does not belong here.

The manifest, `plugin.yml`, declares status and inspect as observable, so
MASTER's guarded observation tool may call them. Login and the two writes run
only through an explicit plugin run. The code is in `social_browser.rb`.

## Use

Inside a MASTER session, the plugin command reaches it.

```text
/plugin info social_browser
/plugin run social_browser status
```


### Soulseek

<sub>Consolidated project reference.</sub>

MASTER connects to an existing [slskd](https://github.com/slskd/slskd) daemon through its versioned HTTP API. slskd owns the Soulseek network session and transfer engine; MASTER owns command admission, local collection inventory and the acquisition boundary.

## Configure

Install and configure slskd natively on the workstation. Keep its web/API listener bound to loopback unless a remote endpoint is required. Create an API key with the minimum required read/write role, then export it only in the MASTER process environment:

```sh
export MASTER_SLSKD_URL=http://127.0.0.1:5030
export MASTER_SLSKD_API_KEY='your-slskd-api-key'
MASTER/bin/master
```

The default endpoint is loopback HTTP on port 5030. A remote endpoint must use public HTTPS on port 443 and pass MASTER's pinned-address SSRF guard. Do not expose the slskd API directly to the public internet. The API key is never written to repository files or plugin state. Search results are limited to unlocked audio files; MASTER also checks slskd's `isLocked` flag before listing or queueing a result.

## Actions

```text
/plugin info soulseek
/plugin run soulseek status {}
/plugin run soulseek search {"query":"J Dilla Jay Dee"}
/plugin run soulseek discover {"queries":["J Dilla breakbeats","jazz funk drum breaks","Bergen soul jazz records"]}
/plugin run soulseek results {"search_id":"<UUID returned by search>"}
/plugin run soulseek rank {"search_id":"<UUID returned by search>"}
/plugin run soulseek downloads {}
/plugin run soulseek library {"path":"~/Music"}
/plugin run soulseek gaps {"path":"~/Music","queries":["J Dilla - Welcome 2 Detroit","Hugh Mundell - Africa Must Be Free"]}
/plugin run soulseek queue {"search_id":"<UUID>","username":"<peer>","filename":"<exact result path>","size":1234567,"rights_basis":"artist_authorized","consent":true}
```

Library scans read filenames and sizes only. They do not open, tag, move, rename or delete audio. Gap matching is a filename heuristic, not an audio fingerprint or proof that two releases are identical.

## Rebuild and audit a collection

Compare existing path-list exports without counting directory names as tracks:

```text
/plugin run soulseek manifest {"paths":["~/MusicExports/0day.txt","~/MusicExports/samples.txt","~/MusicExports/reggae.txt"]}
```

Build a structured catalogue from an actual local music folder. Create the destination directory first; exports are written outside the music folder and require explicit consent:

```text
/plugin run soulseek catalog {"path":"~/Music","output_path":"~/.master/music/catalog.json","consent":true}
/plugin run soulseek duplicates {"path":"~/Music","mode":"candidates"}
/plugin run soulseek duplicates {"path":"~/Music","mode":"sha256"}
/plugin run soulseek quality {"path":"~/Music"}
```

The catalogue groups files by their containing folder and records relative paths, sizes, formats and filename-derived artist/album/title/year hints. It reports folders without clear artist/year hints and tracks without a track-number hint. These are naming-based metadata gaps, not a scan of embedded ID3/Vorbis/MP4 tags; it does not read embedded tags or audio. Manifest comparisons report exact path overlap only; different paths do not establish different recordings. Duplicate candidates share a normalized filename and size, while `sha256` verifies byte-identical content by reading each audio file. Hashing can take time on large libraries. Both modes are reports only: nothing is deleted or reorganised. Existing catalogue files are not overwritten unless `overwrite: true` is also supplied with consent.

The `quality` action is structural triage: it reports common extension families, empty files and very small files for manual review. It does not decode audio or establish bitrate, sample rate, clipping or audible fidelity; small files may be intentional samples or short clips.

### Sample discovery and evaluation

`discover` submits 1–20 explicit Soulseek searches in one bounded invocation. It deduplicates exact repeated queries and returns one search ID per query; it does not wait for peers or download anything. Inspect those IDs with `results`, or use `rank` to sort the returned files by a provisional priority score based on extension, peer-reported sample rate/bit depth/bitrate and reported free slots. All peer metadata is unverified: the score is a shortlist aid, not proof of losslessness, recording quality or provenance.

After a rights-cleared file has completed through slskd, pass a local WAV copy to STUDIO's analyzer:

```text
/plugin run soulseek analyze {"path":"~/Music/Downloads/approved-break.wav","max_duration":30}
```

The read-only `analyze` action currently accepts PCM or IEEE-float RIFF/WAVE files up to 32 MiB and analyses at most 30 seconds. It refuses to run on OpenBSD hosts so this CPU- and memory-bounded work stays on the workstation or an isolated sandbox, never vm23. It verifies that the file remains unchanged during the run, records its SHA-256 and WAV format/sample-rate/bit-depth/channel metadata, and uses STUDIO's existing Ruby analyzer for tempo, onset, harmony, spectral and section features plus measured peak, RMS, clipping and near-silence statistics. It does not classify noise, certify fidelity or replace listening. Convert other formats to a local WAV derivative with an operator-installed audio tool before analysis; preserve the downloaded original.

The full sequence is therefore discovery, peer-result review, one rights-cleared download, then local technical analysis. Search and ranking never trigger acquisition; bulk acquisition remains disabled.

Search and result inspection do not download files. Queueing requires explicit `consent: true`, the exact unlocked filename and size from the named search result, and a rights basis admitted by MASTER's canonical plugin policy (`public_domain`, `open_license`, `artist_authorized` or `rights_owned`). One file is queued per call. Bulk acquisition is disabled. The rights basis is an operator attestation, not a legal determination; personal possession or personal-use intent alone is not a rights basis.

MASTER does not bypass peer queues, locked shares, DRM, paywalls or access controls. Verify the recording, edition, source and licence before queueing. slskd's configured download directory and transfer limits remain authoritative.


### tap_probes (parked)

<sub>Consolidated project reference.</sub>

Parked focus-walk and tap-target browser probes.

- **revive_when:** mobile face work resumes
- **members:** checks/focus_walk_probe.rb, checks/tap_target_probe.rb
- **note:** Removed from checks.yml (hard) and check_tiers.yml (soft). lib/fix tap-target padding stays in the tree.

Parked 2026-11-01 under the essentials pass; sponsor: the operator.


### Travel Browser

<sub>Consolidated project reference.</sub>

**Travel Browser lets MASTER do the searching, comparing and form-filling of a
trip, and leaves the one act that spends money, and every secret on the way to
it, in the hands of the person who is going.**

It drives a visible browser, through the Ferrum gem, for flights, hotels,
restaurants, tours and transfers. It works on any site that has a page, because
it automates the page and not a provider's private interface. A provider with a
stable authenticated API and a stronger contract may get its own adapter later.

The actions are status, inspect, open, login, fill, click and book. Open
accepts HTTPS addresses only and passes them through the same guard that blocks
loopback, private and reserved destinations. Inspect returns the page title,
its text, up to 120 of its form controls and a screenshot. Page text passes
through the injection guard and is treated as untrusted content, never as
instruction. Each browser action keeps a named session, a profile stored under
`~/.master/plugins/travel_browser/sessions/` with owner-only permissions. The
repository holds no credentials and no booking state.

Secrets stay with the operator. Login waits in the visible browser while the
operator types credentials and one-time codes, and MASTER receives none of
them. The fill action refuses any selector that names a password, one-time
code, card, security code or passport field, so those fields can only be filled
by hand. A CAPTCHA, an access-denied page or any other security challenge stops
the run and waits for a person.

The book action is the final check. It does nothing unless the call carries
confirm_purchase set to true, and it compares the total on the page with the
expected total when the caller supplies one. A mismatch refuses the click. The
result holds the URL, the page title, the visible total and screenshots from
before and after. It states that the submission happened and that the
confirmation page or the booking email must prove the rest. A click alone is
never reported as a booking.

The rules are declared in `data/laws.yml` under the travel_browser policy, and
the manifest, `plugin.yml`, marks only status and inspect as observable. The
other five actions run only through an explicit plugin run. The code is in
`travel_browser.rb`.

## Use

Inside a MASTER session, the plugin command reaches it.

```text
/plugin info travel_browser
/plugin run travel_browser status
/plugin run travel_browser open {"session":"trip","url":"https://example.com"}
```


### tts_dsp (parked)

<sub>Consolidated project reference.</sub>

Parked TTS benchmark/measure/quality suite and tts-e2e gate.

- **revive_when:** the first external listener; the TTS worker itself stays in the tree
- **members:** tools/voice/{voice_benchmark,voice_measure,voice_quality}.rb, tools/ shims, bin/tts-e2e, 2 tests
- **note:** Rakefile task and smoke --tts step removed; smoke command inventory row removed.

Parked 2026-11-01 under the essentials pass; sponsor: the operator.


### video_recordings (parked)

<sub>Consolidated project reference.</sub>

Parked session/face video recorders, capture probe and README media tooling.

- **revive_when:** the face ships to a real visitor and needs regression capture
- **members:** checks/face_loop_record.rb, checks/shell_loop_record.rb, checks/face_capture_probe.rb, bin/loops, readme_take.rb
- **note:** Path roots resolve from the plugin owner; the plugin remains parked outside checks.yml and smoke --tts.

Parked 2026-11-01 under the essentials pass; sponsor: the operator.


### Tools

<sub>Consolidated project reference.</sub>

**MASTER keeps its instruments in plain sight and holds them to the same
standard as the code they measure, because a measurement nobody has checked is
only an opinion that happens to carry a number.**

This directory contains the operators, scanners, audits and inventories
that maintain the repository. Most are small Ruby programs with one clear
responsibility. The operator exposes the main entrypoints:

- `bin/operator measure` reports the ratchets and measurements.
- `bin/operator lint` applies the Laws without a model.
- `bin/operator doctor` checks the environment for known hazards.
- `sweep.rb` runs the census instruments in one pass and writes their
  findings in dmesg form. It measures and proposes; it never edits.

## Directory map

- `audit/` contains substantive registry, reachability and hygiene audits.
  Stable one-command endpoints whose implementations already live in
  `lib/` remain at this directory's top level. The former root paths for
  the audit family were removed; no compatibility entrypoints remain.
- `repo/` contains tracked-tree inventory and entrypoint reachability. `snapshot.rb` remains a top-level
  operator command until its reader/writer contracts are verified
  independently.
- `research/` contains cognition outcome benchmarks, mutation-oriented
  challenge checks and LLM trajectory reports.
- `audit/design_baseline.rb` measures the repository's design baseline.
- `rails/` contains Rails tooling. The operator exposes it through
  `triangle` (boot the live Brgen, Amber, BSDPorts and MASTER-face
  entries), `premerge`, `ci` and `coverage`. The same directory builds
  stylesheets and the route manifest, crawls apps with a browser, and holds
  Rails convention checks.

Several top-level tools serve cross-tree contracts:

- `agent_context.rb` prints the Law and tree map agents must read before
  working. Its `--json` option serializes the same standing context
  (conduct, blocking rules, coverage and shell contract); `--tree` adds
  the selected tree map. Harnesses and session handoffs can consume the
  JSON without parsing prose.
- `coverage_reconciliation.rb` compares tracked files with the instruments
  claimed in `checks/data/coverage_map.yml`. It reports INCONCLUSIVE while
  that map is marked partial, then fails on uncovered files once the map
  declares itself complete.
- `diff_routes.rb` accepts paths, a `--diff` base or `--stdin`, then
  prints the governing `PATH_OWNERSHIP.yml` rows and their declared checks.
  It exits 1 and names any path no row claims. It does not add a second
  path-to-check table.
- `snapshot.rb` backs `bin/operator snapshot`. It writes one snapshot per
  tree for another model to read; `--mirror` creates the byte-exact pack.
- `gap_discipline.rb` checks the chain from absence to implementation:
  `data/gaps.yml` identifies missing capabilities;
  `data/ideations/*.yml` records candidates and the reasons losers were
  rejected; `convergence.yml` records the resulting workstreams. It fails
  when critique rejects a picked candidate, a real choice has too few
  candidates, a picked gap has no workstream, or a workstream has no
  corresponding gap.

Media implementations belong to `STUDIO/`. The two compatibility links
that remain here are `dilla` and `replicate`; STUDIO owns their targets and
contracts. Invoke Postpro through `STUDIO/postpro`, not through a MASTER
link. Read the owning project README before changing media behavior. Do not
add a second implementation here.

## Read this part first

A measurement can be wrong even when its output looks precise. Before
trusting a finding, compare the instrument's source with a case whose answer
you already know. A greyscale test image once made a colour effect look dead.
A parallel sum changed in its last digit even when the input stayed steady.
When the result is unstable, hash the output and investigate the source of
the variation.

Declarations with no reader are the dominant defect. A preset names a setting
that no effect consults, a call passes an argument that the callee does not
accept and a rescue hides the error, and the feature never runs while every
report says it did. Before you trust a setting, find its reader. Before you add
a fix, consider adding the check that would have caught the fault.

Use Ruby and zsh, not GNU text tools. The repository deploys to OpenBSD, where
sed, awk, find, head, tail and wc behave differently, and perl and python are
banned in shell calls and committed scripts.

Tests here must prove something. `mutate.rb` changes a source, runs its test and
restores the file, because a test that stays green when the comparison it
covers is inverted proves nothing. Run the smallest check that proves the
work, and do not report done without its output.

## Checks

The Rakefile in this directory defines the checks. The test task runs the check
and event-bus suites, and the check task parses and loads every tool.

```zsh
cd MASTER/tools && rake test
cd MASTER/tools && rake check
```

The browser runtime is conversation-only: public web search, scoped dialogue, voice, and the particle face. Operator commands, schedulers and filesystem tools belong to the local CLI. Battery status is local and omitted when unsupported; the camera-shaped control opens the native photo picker, not a live camera. The canonical face uses deterministic particle geometry; see [Web face](#web-face-sculptural-particle-stipple).

Native OpenBSD web sealing is available for rehearsal with `MASTER_WEB_NATIVE_SANDBOX=1`: `unveil(2)` limits paths and `pledge(2)` removes process execution. It requires a provisioned web auth token and an independently supervised TTS socket (the web process cannot restart the voice worker after sealing). It remains disabled until the production Falcon, SQLite, pairing, provider and voice paths pass on-host verification. `/health` reports observed native sandbox state.

Browser pairing codes and tokens are confined to the web runtime state directory; they cannot authorize local messaging or operator tools. Existing browser pairings must be reissued through the web pairing admin. Native sandbox rehearsal additionally requires `MASTER_AUTH_CONFIG` to point to a provisioned web-only token file inside `web/tmp/public_runtime`, not the CLI configuration.
