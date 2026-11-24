# pub5 law adherence — a ruthless three-axis audit

**Analyzed:** origin/main @ `4514f01d` (2026-11-23 08:30 UTC), the same tree as the deploy review. **Method:** static reads and mechanical recounts against `MASTER/data/laws.yml` (8,092 lines), `soul.yml`, `MASTER/law/*.rb` (549 `Law.define`s), and the trees they govern. No Ruby in this sandbox — runtime-computed values are marked NOT_RUN and, where possible, reproduced statically instead. **Trace:** every network operation and every command behind every number in this report is listed, with its output, in Appendix A.

The framing law is DUAL_MODALITY: "The registry audit reports what actually runs and measures each gap." This audit applies that sentence to the constitution itself. Credit first: catalogue integrity is genuinely clean — **0 dangling definition sources, 0 severity mismatches between statement rows and catalogue, 0 duplicate definitions** (the 11 apparent misses are dynamic definitions: `Law.define(:"RAMS_#{trait}")`, locale-generated prose IDs). The machinery that checks the catalogue works. What sags is everything the catalogue says about itself and about the trees.

---

## 0. The constitution's own scoreboard vs. my recount

| Instrument | laws.yml records | Static recount @ `4514f01d` | Verdict |
|---|---|---|---|
| `RATCHET_DEPS_UNGRAPHED` (statement: "dangling after targets") | value **132** | **17** dangling `after:` targets (10 case-insensitive) — and **no code anywhere recomputes this number** | Stale and instrumentless: a ratchet value nothing can reproduce is an unverified claim under its own TRUTHFUL_STATUS |
| `law_ratchets.deps.ungraphed` (registry laws with no `law_deps` key) | ceiling **194** | `law_deps` has **35 keys for 549 defined laws** (~6% graphed) | The ceiling holds; the graph is a skeleton wearing a graph's name |
| `RATCHET_DUALITY_MECHANICAL_GAP` / `SEMANTIC_GAP` | 12 / 9 | **418 of 549** defined laws have no mechanical `check` block; 271 have no `ask`/`practice` | Runtime-computed (NOT_RUN), but no population definition reconciles 12 with the tree |
| `self_findings.yml` ceiling | **31,585** findings, 145 rules | Sampled 200 recorded `TRAILING_WHITESPACE` members: **0 still violate**. Sampled `LONG_LINE`: ~37% still real | The ceiling is stale in both directions — it confesses thousands of already-served sentences |
| `ratchets.rb` comments | "the **122** laws" and "the **145** rules" describing the same population | 145 rules have findings; nothing is 122 | Two numbers, one population, one file |
| `LAW_MAP` self_test | "every law id resolves" | law_map: 291 meaning rows, **146 marked `status: gap`**, `law_trace_ceiling: 88` | Honest — but half the meaning-map is declared aspiration, and the trend is unpublished |

The header of `self_findings.yml` says the quiet part: "the rise is the instrument's and not the code's… From here the ratchet only falls." A ceiling recorded above reality, that may only fall, with no scheduled re-measurement, is a ratchet that has stopped pulling.

---

## 1. Lexical adherence — the words

**1.1 The PUB4 ghost — 226 matches in a repo named pub5.**
`PUB4` env var (`${PUB4:-/home/dev/pub5}` in `RAILS/_assets.sh`, `_sync.sh`), `PUB4_CI_GUARD` in `vps_ci.sh` and `__shared/config/ci.rb`, the `pub4-rails` mirror directory in `ci-sync.ksh`, `pub4_rcctl` in `_deploy.sh`, plus litter across tests, tools, and `laws.yml` itself (line 5369). The laws this violates are its own: SINGULARITY_one_true_mark, RENAME, STEWARDSHIP_mono_no_aware.
**Ruthless fix:** one `RENAME` transformation pass — `PUB4` → `PUB5`, `pub4-rails` → `pub5-rails`, `pub4_rcctl` → `pub5_rcctl` — behind a one-release compatibility shim that warns on the old names, then delete the shim. Then a permanent lint: the string `pub4` outside git history is a build error. A rename you don't finish is two names.

**1.2 `Operator::LawInventory.rule_dependencies` returns garbage.**
`law_inventory.rb:223`: `deps.transform_values { |value| Array(value).map(&:to_s) }` — `value` is the whole `{"after" => [...]}` hash, so `Array(hash)` yields key-value pairs and every law's `dependencies:` renders as the string `'[:after, ["HOIST"]]'`. The operator's own `bin/operator laws <id> --card` prints stringified Ruby where the dependency list should be.
**Fix (one line + one test):** `Array(value["after"]).map(&:to_s)`.

**1.3 Stale scoreboards are lexical lies at rest.**
Every number in §0 that no instrument can recompute (132, 12, 9, the 31,585 ceiling) is a sentence in a data file that the tree no longer supports. Under TRUTHFUL_STATUS_unverified_claim these are findings, not metadata.
**Ruthless fix:** re-record nightly; stamp each recorded value with the instrument version that produced it; make `--ratchet` refuse any value whose reproduction differs by more than the recorded tolerance. The instrument's confession should expire like the OpenBSD receipt does.

**1.4 Small drifts worth one sweep each:** "122 laws" vs "145 rules" in `ratchets.rb`; `VERSION` 1.0.3 vs soul `version: 3.0.0` (different objects — fine until a report prints one where it means the other); the retired `TYPOGRAPHIC_GRID` still holding 1,711 recorded findings (a dead law with a live rap sheet).

---

## 2. Conceptual / semantic adherence — the meaning

**2.1 The mechanical floor is closer than the constitution admits.**
`self_test` (laws.yml:5718) requires `KERNEL_ADHERENCE: law adherence >= 35%`, and `adherence_pct` counts only deterministic detectors. Statically: **131 of 549 `Law.define`s carry a `check` block (~24%)**; the balance must come from the scanner registry. Either the registry contributes ~60+ scanner-only rules and the floor is barely met, or the constitution operates at/near its own red line and nothing alarms.
**Ruthless fix:** print `adherence_pct` and the mechanical/semantic populations in the header of every `bin/operator laws --health` and every preflight report; make a drop below 35% a deploy-blocking preflight failure, not a rake curiosity (`rake lint:law_reach` that nobody runs is a smoke detector in a drawer).

**2.2 418 laws are prompts, not programs.**
Three quarters of the defined laws have no mechanical check — each is judged by an LLM semantic adapter or a human, per catalogue entry, per corpus pass. That is cost, non-determinism, and silent drift: the same file can pass Tuesday and fail Thursday, and `detection_calibration` can't bind a moving target.
**Ruthless fix:** triage all 418 into exactly three fates — (a) grow a `check` (the big whitespace/typography/quotes families are mechanically decidable and hide behind semantic classification), (b) demote to `practice` guidance (admitted advice, not law), or (c) keep semantic with a recorded calibration fixture and an expiry, applying ROBUSTNESS_exemption_without_expiry inward. Batch 25 at a time, highest self-findings first: CONSECUTIVE_BLANK_LINES (2,200), VERTICAL_BREATH (2,289), TRAILING_WHITESPACE (2,168), QUOTES_BY_LOCALE (1,566) — most of which are autofix-mechanical and would make the ceiling fall thousands for free.

**2.3 The dependency graph is decorative.**
35 of 549 laws are graphed; **17 `after:` targets name laws that don't exist** (`HOIST_CONSTANTS`, `EXTRACT`, `OMIT_NEEDLESS`, `ACTIVE_VOICE`, `bare_rescue`, `god_class`, `long_method`…), and `fix_loop/order.rb` topologically sorts on them without validation — phantom edges silently misorder the fix loop.
**Fix today:** delete or re-point the 17 dangling targets (10 minutes, zero runtime risk). Then either grow the graph to cover the transformation and hygiene families or delete `law_deps` and stop paying for a skeleton.

**2.4 Retired laws that won't die.**
Four catalogue entries carry `lifecycle: retired` — `ALL_CAPS_NO_TRACKING`, `JS_MODULE_SIZE`, `SMALL_FILES`, `TYPOGRAPHIC_GRID` — with detectors still loaded and, in one case, 1,711 findings still recorded. Under DENSITY_dead_code a constitution that keeps dead laws teaches every reader that "retired" is decorative.
**Fix:** remove the entries and their `Law.define`s in one commit; git history already holds them (its declared role).

**2.5 One law's mechanical enforcement is a human.**
`DO_THE_WORK_NOW` declares `mechanical: human` — the ratchet claims twelve such; statically I find one. Whichever is right, the record and the reality disagree, which is the finding.

**2.6 The 23 `opportunity`-mode laws are orphans.**
`SIGNATURE_MOMENT`, `STATE_CHOREOGRAPHY`, `VISUAL_HIERARCHY`, `CORE_WEB_VITALS`… nothing in the violation-driven pipeline ever fires them. Decide: wire an opportunity report into `bin/operator check`, or admit they're prose and move them to the design library where prose belongs.

---

## 3. Visual adherence — the render

**3.1 MASTER/web's face is token-disciplined with 196 exceptions.**
13 stylesheets, **1,181 `var(--` uses** — the DESIGN_TOKEN_ARCHITECTURE_IS_SINGULAR law is mostly lived. The residue: **196 px values off the 4px rhythm** (18px ×13, 14px, 13px, 1.5px…, against PROPORTION_eight_px_rhythm / BASELINE_SPACE_MULTIPLES), and **70 hardcoded hex colors** — including `#000` ×22 and `#000000` ×3 (the same black spelled two ways: a DRY violation in CSS), plus semantic colors hardcoded in the wscons skin (`--c-text: #63c363`, `#e46151` red) that belong in the token layer like the other modes.
**Ruthless fix:** collapse duplicate spellings into tokens (mechanical), route the two semantic colors through tokens, then make the existing `DesignTokens.scss_anchor_drift?` check **fail** `bin/operator premerge` instead of advising — today nothing stops a raw hex from shipping, which is why 70 exist.

**3.2 RAILS __shared SCSS is nearly clean — finish it and lock it.**
96 hex definitions in `_tokens.scss`, only **12 hardcoded hexes in 4 consumer files** (`_shell.scss` 5, `_search_yep.scss` 3, `_embeds.scss` 2, `_empty_state.scss` 2). Twelve edits and the shared design system is 100% token-conformant; the drift check then holds the line forever. Highest-value-per-minute fix in this whole report.

**3.3 The typography laws are the most-violated family in the house.**
`QUOTES_BY_LOCALE` 1,566, `TYPOGRAPHIC_GRID` 1,711 (retired law, live findings), `ELLIPSIS_SPACE_BEFORE` 65, `NO_SPACED_EM_DASH` 263, `NO_ASCII_LINE_ART` 278 + `NO_ASCII_ART_OUTSIDE_FACE` 41 — and the registry findings for ASCII art sit in `MASTER/law/definition.rb` and `cosmetic.rb` themselves. The law files break the art law in the act of defining it.
**Ruthless fix:** quotes/dashes/ellipses are mechanically autofixable — run one `--mode=repair` sweep per law, drop the ceiling by ~2,000 in a day, and either exempt law fixtures from the art law explicitly or redraw the diagrams. A constitution that excuses itself teaches nothing.

**3.4 `CHROME_COPY_CALM` / `ACTION_LABEL_BRIEF` have only 6 recorded findings** — either true or unmeasured; with a 31,585-finding ceiling stale in both directions, nobody knows. That's the argument for §1.3 again, wearing a visual coat.

---

## The program, in order

**Phase 0 — today, mechanical, zero runtime risk** (~1 hour):
1. Fix `rule_dependencies` (one line) + regression test.
2. Delete the 17 dangling `law_deps` after-targets.
3. Token-ize the 12 RAILS SCSS hexes; collapse `#000`/`#000000` duplicates in MASTER/web.
4. Re-record `self_findings.yml` and every ratchet value from a live run, stamped with instrument version. The scoreboard tells the truth at least once.

**Phase 1 — this week:**
5. The PUB4→PUB5 rename sweep with shim, then shim deletion and a permanent `pub4` lint.
6. Remove the 4 retired catalogue entries and their detectors.
7. Make `DesignTokens.scss_anchor_drift?` and `adherence_pct < 35%` blocking in premerge/preflight.
8. One `--mode=repair` sweep each for TRAILING_WHITESPACE, CONSECUTIVE_BLANK_LINES, QUOTES_BY_LOCALE — the ceiling falls thousands for free.

**Phase 2 — this month:**
9. Triage the 418 semantic-only laws, 25 at a time: mechanical check, practice demotion, or calibrated fixture with expiry.
10. Grow `law_deps` from 35 to cover the transformation and hygiene families — or delete it.
11. Nightly re-recording of all ratchet values with instrument-version stamps, so an instrument change can never again be recorded as a code change.
12. Decide the fate of the 23 opportunity-mode laws: wire them into reporting or move them to prose.

**Honesty footer:** catalogue-integrity counts, law_deps recounts, `Law.define` block analysis, CSS measurements, self-findings sampling, and the `rule_dependencies` bug are all static and reproducible from the tree. NOT_RUN (no Ruby here): the runtime registry audit (`adherence_pct`, blind/saturated, the true duality-gap counts), the actual `SelfFindings.members` recount, and every test that should accompany the Phase 0 fixes. Where my static recount disagrees with a recorded ratchet value, treat the recorded value as suspect and reproduce it before trusting either of us.

---

## Appendix A — evidence: every network operation and command taken

Per this repo's own evidence rules (TRUTHFUL_STATUS_causal_trace_is_evidence: command output establishes what ran), here is the complete trace. Everything ran in an isolated Linux sandbox (no Ruby, no repo push access). The analyzed tree lived at `/tmp/pub5-new`.

### A.1 Network operations (the complete outbound list)

| # | Operation | Result |
|---|---|---|
| N1 | `curl -sL --max-time 300 -o pub5.tar.gz https://github.com/anon987654321/pub5/archive/refs/heads/main.tar.gz` | 84 MB tarball → extracted to `/tmp/pub5` (initial checkout, earlier session phase) |
| N2 | `curl -s --max-time 30 "https://api.github.com/repos/anon987654321/pub5/commits/main"` | HEAD = `4514f01da86b2aff16bba05afa58b1a7a49cc7fb`, 2026-11-23T08:30:03Z, "Test exact full-stack redeploy wording" |
| N3 | `curl -sL --max-time 300 -o pub5-new.tar.gz https://github.com/anon987654321/pub5/archive/refs/heads/main.tar.gz` | refreshed tarball → `/tmp/pub5-new`; `diff -rq /tmp/pub5 /tmp/pub5-new` showed main had moved (36 files), so all audit work used `/tmp/pub5-new` |
| N4 | `curl -s --max-time 30 "https://api.github.com/repos/anon987654321/pub5/commits?per_page=15"` | commit list 08:20–08:30 UTC (RTFM gate, STUDIO proof, wording tests) |
| N5 | `curl -s --max-time 30 "https://api.github.com/repos/anon987654321/pub5/commits/main"` (repeat, immediately before this audit) | HEAD unchanged (`4514f01d…`) — the tree did not move during analysis |

Failed/blocked network operations (why some things are NOT_RUN):

| # | Operation | Result |
|---|---|---|
| F1 | `git clone https://github.com/anon987654321/pub5.git` (×2) | `gnutls_handshake() failed` — fell back to tarball (N1) |
| F2 | `apt-get install ruby` | "Package 'ruby' has no installation candidate" (restricted Debian 12 sources) — **no Ruby in sandbox, ever** |
| F3 | `curl` of `ruby-builder` prebuilt Ruby tarball (×3, up to 600 s timeout) | deadline exceeded each time — Ruby execution remained impossible; every runtime value in this report is static recount or NOT_RUN |

No other hosts were contacted. No writes, pushes, or deploys were performed against GitHub or vm23.

### A.2 Tree acquisition and integrity

```sh
mkdir -p /tmp/pub5-new && tar xzf pub5-new.tar.gz -C /tmp/pub5-new --strip-components=1
diff -rq /tmp/pub5 /tmp/pub5-new            # identified the 36 changed files; findings re-verified on the new tree
wc -l /tmp/pub5-new/MASTER/data/laws.yml /tmp/pub5-new/MASTER/data/soul.yml /tmp/pub5-new/MASTER/data/law/TREE_CONTRACTS.md
# 8092 laws.yml, 153 soul.yml, 960 TREE_CONTRACTS.md
```

### A.3 Catalogue population counts (YAML-derived)

Run with Python 3.12 + PyYAML against `MASTER/data/laws.yml`:

```python
import yaml, collections
laws = yaml.safe_load(open('MASTER/data/laws.yml'))
rows  = {k: v for k, v in laws.items() if k != 'law_catalogue'}
cat   = laws['law_catalogue']; e = cat['entries']
merged = {k: {**cat['defaults'], **v} for k, v in e.items()}   # defaults: mode violation, lifecycle active, autofix review
collections.Counter(v['autofix']    for v in merged.values())  # review 449, automatic 79, never 32
collections.Counter(v['lifecycle']  for v in merged.values())  # active 532, trusted 16, advisory 8, retired 4
collections.Counter(v['mode']       for v in merged.values())  # violation 537, opportunity 23
len([k for k, v in rows.items() if isinstance(v, dict) and 'statement' in v])   # 346 statement rows
```

Integrity checks:

```python
import os
[(k, s) for k, v in e.items() for s in v['definition_sources']
        if not os.path.isfile(os.path.join('/tmp/pub5-new', s))]                 # [] — 0 dangling
[(k, rows[k]['severity'], merged[k]['severity']) for k in rows
 if isinstance(rows[k], dict) and 'severity' in rows[k] and k in merged
 and merged[k].get('severity') and merged[k]['severity'] != rows[k]['severity']] # [] — 0 mismatches
```

### A.4 Law registry recount

```sh
grep -rhoE 'Law\.define\(:[A-Za-z0-9_]+\)' /tmp/pub5-new/MASTER/law/*.rb | sort -u | wc -l   # 549, 0 duplicates
```

The 11 catalogue IDs with no literal define (PROSE_ACTIVE_VOICE*, PROSE_OMIT_QUALIFIERS*, RAMS_HONEST/THOROUGH/UNDERSTANDABLE/UNOBTRUSIVE/USEFUL) were cleared by:

```sh
grep -n 'Law.define' /tmp/pub5-new/MASTER/law/prose.rb    # line 108/135: Law.define(language["ids"][...].to_sym) — generated per locale
grep -n 'RAMS_' /tmp/pub5-new/MASTER/law/surface.rb       # line 622: Law.define(:"RAMS_#{trait}") — generated per trait
```

Modality recount (block-level regex split on `Law.define(`, then scan each block for `check do`, `ask`, `practice`):

```python
# defined laws with no mechanical check block: 418
# defined laws with no ask/practice:           271
```

### A.5 law_deps recount (the 132-vs-17 discrepancy)

```python
deps = laws['law_deps']                       # 35 entries
registered = set(rows) | set(e) | defined_ids # statement rows + catalogue + Law.define IDs
[(l, t) for l, spec in deps.items() for t in (spec.get('after') or []) if t not in registered]
# 17 dangling targets: MERGE→HOIST_CONSTANTS, COMMENTS_AS_DEODORANT→EXTRACT, ACTIVE_VOICE→OMIT_NEEDLESS,
# PARALLEL_STRUCTURE→ACTIVE_VOICE, bare_rescue→fail_visibly, silent_rescue→bare_rescue, god_class→small_functions,
# god_class→nesting_depth, long_method→nesting_depth, n_plus_one→find_each, veto_patterns→yaml_declarative,
# interconnect→rule_coverage, KISS→long_method, SRP→god_class, LISKOV→god_class, html_lang→meta_charset,
# no_inline_styles→magic_color      (10 of the 17 also fail case-insensitively)
```

Consumers verified by grep:

```sh
grep -rn 'law_deps' /tmp/pub5-new/MASTER/lib --include='*.rb'
#   lib/fix/fix_loop/order.rb:144-148  load_deps — consumes after-targets, NO existence validation
#   lib/review/scan/law_registry_audit.rb:225-231  ungraphed_law_ids — measures registry-minus-deps-keys (the 194 ceiling), NOT dangling after-targets
#   lib/operator/law_inventory.rb:223  rule_dependencies — the stringified-pairs bug
grep -rn 'RATCHET_DEPS_UNGRAPHED' /tmp/pub5-new/MASTER --include='*.rb' | grep -v test   # no measuring code — nothing recomputes the recorded 132
```

### A.6 Lexical probes

```sh
grep -rn 'PUB4\|pub4' /tmp/pub5-new/MASTER /tmp/pub5-new/RAILS /tmp/pub5-new/OPENBSD \
  --include='*.rb' --include='*.sh' --include='*.ksh' | wc -l                          # 226
grep -rln '/home/dev' /tmp/pub5-new/MASTER/lib /tmp/pub5-new/MASTER/web /tmp/pub5-new/RAILS \
  --include='*.rb' --include='*.sh'                                                    # 18 files (mostly deliberate box-side constants)
grep -rn '\bputs\b' /tmp/pub5-new/MASTER/lib --include='*.rb' | wc -l                  # 148 (CLI-output exemptions apply)
grep -rnoE '\b(will|would|could|might)\b' /tmp/pub5-new/MASTER/web/app/views \
  /tmp/pub5-new/MASTER/web/app/javascript | wc -l                                      # 1 (benign prose, chat/index.html.erb:109)
grep -rn '122 laws\|145 rules' /tmp/pub5-new/MASTER/lib                                 # both in lib/operator/ratchets.rb comments
```

### A.7 Visual probes

```sh
find /tmp/pub5-new/MASTER/web -name '*.css' -o -name '*.scss' | wc -l                  # 14 (13 styles/ + public/)
grep -rho 'var(--' /tmp/pub5-new/MASTER/web/styles /tmp/pub5-new/MASTER/web/public | wc -l   # 1181 var(-- uses
grep -rhoE '#[0-9a-fA-F]{3,8}\b' ... | sort | uniq -c | sort -rn                       # 70 raw hexes; #000 ×22, #000000 ×3,
                                                                                       # #63c363 ×2, #e46151 ×1 (wscons skin)
grep -rn '#face' /tmp/pub5-new/MASTER/web/styles/                                      # cleared: id selectors (canvas#face etc.), not colors
grep -rhoE '[0-9]+(\.[0-9]+)?px' ...                                                   # 638 px values; 196 off the 4px rhythm
                                                                                       # (1 ×75, 2 ×58, 18 ×13, 13 ×7, 14 ×6, 1.5 ×6, …)
grep -rhoE '#[0-9a-fA-F]{6}\b' /tmp/pub5-new/RAILS/__shared/app/assets/stylesheets/ | sort | uniq -c | sort -rn
# 96 definitions inside _tokens.scss; exactly 12 in consumers (_shell 5, _search_yep 3, _embeds 2, _empty_state 2)
```

### A.8 Self-findings staleness sampling

```python
sf = yaml.safe_load(open('MASTER/data/self_findings.yml'))     # findings: 31585, 145 rules
tw = [m for m in sf['finding_members'] if m.startswith('TRAILING_WHITESPACE')]   # 2168 recorded
# for 200 sampled members: open(path).readlines()[line-1] → trailing space? → 0 still violate, 0 missing files
ll = [m for m in sf['finding_members'] if m.startswith('LONG_LINE')]             # 4582 recorded
# for 200 sampled members: len(line) > 120? → 75 still violate (~37%)
```

Independent reproduction against the live trees:

```sh
grep -rn ' $' /tmp/pub5-new/MASTER/lib /tmp/pub5-new/RAILS/*/app /tmp/pub5-new/RAILS/__shared \
  /tmp/pub5-new/STUDIO /tmp/pub5-new/MASTER/web --include='*.rb' --include='*.erb' \
  --include='*.scss' --include='*.css' | wc -l                                        # 0 — the recorded 2168 are all served
grep -rn -A15 'define(:LONG_LINE)' /tmp/pub5-new/MASTER/law/lexical.rb                # threshold: >120 chars
```

### A.9 Scoreboard and consumer reads (file:line)

```sh
grep -n -A6 '^RATCHET_'  /tmp/pub5-new/MASTER/data/laws.yml     # values: DEPS_UNGRAPHED 132, DUALITY 12/9, rest 0
sed -n '6027,6048p'      /tmp/pub5-new/MASTER/data/laws.yml     # law_ratchets.deps.ungraphed ceiling 194 (+ its own
                                                                # comment admitting the two metrics share one name)
sed -n '5711,5726p'      /tmp/pub5-new/MASTER/data/laws.yml     # self_test: KERNEL_ADHERENCE ">= 35%"
grep -n -B5 -A25 'def ungraphed_law_ids' /tmp/pub5-new/MASTER/lib/review/scan/law_registry_audit.rb
sed -n '221,226p'        /tmp/pub5-new/MASTER/lib/operator/law_inventory.rb   # rule_dependencies bug (line 223)
grep -rn 'mechanical: human' /tmp/pub5-new/MASTER/data/laws.yml               # 1 row: DO_THE_WORK_NOW
```

### A.10 What was NOT run, and why

No `ruby`, `rake`, `bundle`, `bin/ci`, `bin/operator`, `rake lint:law_reach`, precompile, deploy, or `/fix` was executed — F2/F3 above made a Ruby interpreter unavailable in this sandbox, and the sandbox has no SSH path to vm23. Consequently these values are quoted from the tree but not reproduced: the runtime registry audit's `adherence_pct`, blind/saturated counts, the true duality-gap counts (12/9), the live `Operator::SelfFindings.members` recount, and the four retired laws' runtime behavior. To reproduce them on a Ruby-capable host at the same tree:

```sh
curl -sL https://github.com/anon987654321/pub5/archive/4514f01da86b2aff16bba05afa58b1a7a49cc7fb.tar.gz | tar xz
cd pub5-4514f01da86b2aff16bba05afa58b1a7a49cc7fb
MASTER/bin/ruby -I MASTER/lib -e 'require "master"; require "review/scan/law_registry_audit"; \
  r = Master::Review::Scan::LawRegistryAudit.new(root: "MASTER").call; puts r.coverage_line'
MASTER/bin/operator law-weight        # live ratchet recount
rake -f MASTER/tools/rails/Rakefile lint:law_reach 2>/dev/null || true
```
