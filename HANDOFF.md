# HANDOFF — pub5 operating rules

Rebuilt 2026-11-22. The previous handoff was lost with a sandbox recycle
before push; every rule below is re-derived from the surviving scripts,
the remote history and the session record. Nothing here is new policy
except where marked.

## Standing engagement

1. **Repo.** `github.com/anon987654321/pub5`, work on `main`. Trees:
   MASTER (incl. `MASTER/web`), RAILS (`RAILS/**`), OPENBSD, STUDIO.
   `/fix` passes sweep MASTER → RAILS → MASTER/web → OPENBSD → STUDIO
   with model `zai-cli:auto`.
2. **Delivery.** Commit verified, path-scoped units to `main`; use
   `MASTER/bin/operator land -m "<message>" <paths...>` from the shared
   checkout. Push only through the configured SSH agent, approved OS
   credential manager or an approved session credential helper. Never embed
   a PAT in a remote URL or command argument, or expose it in shell history,
   process listings, logs, `.git/config` or a commit. Never save it in the
   repository. If secure authentication is unavailable, do not push; report
   `DELIVERY_FAILED` and preserve the local commit. Treat any PAT pasted into
   a chat or transcript as compromised and rotate it.
3. **Cron 541280** (08:40 / 16:40 / 23:40 Oslo) runs `/fix --no-publish
   --model zai-cli:auto`. It never pushes, never edits by hand; its work
   lands as commits we can accept or revert.
4. **Language.** Plain Strunk-and-White English everywhere: code
   comments, docs, commit subjects.

## STUDIO disciplines

5. **Renders** live inside `STUDIO/*.*` only. Designs obey
   `MASTER/data/laws.yml`. Screenshots are mobile-only, 390x844.
   One animated showcase per app. Selfies come from GLM image models.
6. **Outputs are append-only.** Renders keep seed reproducibility and
   write sidecars (`.quality.json`, `.session.json`, `.provenance.json`).

## Music canon

7. **Tiers.** `[record]`/`[chart]` rows are the performance canon:
   sample-verified artist material and published charts. `[study]`/
   `[original]` rows are legacy engine exercises — never models for new
   work. The engine menu orders tiers
   artist_verified → chart_reference → engine_study → engine → recovered
   (see `STUDIO/dilla/dilla.rb` `progressions`).
8. **Two-source honesty.** Every musical claim cites a published source
   (WhoSampled identifications, Hooktheory TheoryTab charts, Ethan Hein
   transcriptions, Genius sample notes, Soul-Sides). Claims are recorded
   per row in `source_refs` with the exact statement each source
   supports. Unverified claims are labelled, never silently kept.
9. **ORIGINAL AUTHENTICS (rule 11).** Chord progressions are never made
   up. Loops come from tried-and-tested artist material — the favourite
   artists and the artists they sampled. The 2026-11-22 audit lives in
   `STUDIO/dilla/data/recovered_music.json` under `authentics_audit`:
   every render-facing row carries `source_refs`, two misattributions
   were fixed (Herbie flip → Fantastic / FV2 Intro; Riperton → Look of
   Love (Remix)), the Accordion row follows the published Hooktheory
   chart, and `authentics_audit.still_unverified` lists what remains.
10. **Renames.** `untitled_a` is `fantastic_herbie_flip` (the Herbie
    sample is documented on Fantastic and the Fantastic, Vol. 2 Intro).
    `clair_moon` stays as a flagged engine study.
11. **Render protocol.** Authentics rows for renders:
    `time_donut`, `fall_in_love`, `get_dis_money`, `players`,
    `never_catch_me_flylo`. `blue_hour` is the stable internal ID of the original F-minor Dub Study —
    not performance material. Mix protocol owed from the last accepted
    direction: melody restored as a heard layer, bass -14 dB under the
    hierarchy, swing 54±1, iterate-and-keep with sidecars, judged by
    `stem_energy_share`. (Two earlier masters were rejected as "horrible";
    the mix protocol exists so that does not repeat.)
12. **Reference pipeline (operator-directed deep lane).** The operator's
    carefully curated YouTube tracks (recovered verbatim from
    `pub/index.html` at `a3185f4`, `const YOUTUBE_TRACKS`, 22 entries)
    are the canon for Dilla's best work. `STUDIO/dilla/data/
    curated_references.json` holds the list and the operator's narrowed
    picks (players, climax_girl_shit, microphone_master_remix,
    fantastic). The operator-supplied audio is analysed through
    `ruby STUDIO/dilla/dilla.rb reference <URL|FILE> --style j_dilla`.
    The standard-library Ruby analyser measures the complete mix only:
    tempo, swing, onset density, harmony and spectral balance. It does not
    separate stems or claim isolated drum, bass or keyboard measurements.
    Optional URL acquisition uses yt-dlp and local FFmpeg; cookies remain
    operator-supplied through `DILLA_YT_COOKIES=~/cookies.txt`. Two
    curated ids were dead on the 2026-11-22 probe (players, fantastic)
    and need live replacements or the operator's session.
13. **Contract tests.** `STUDIO/replicate/test/dilla_test.rb` pins
    evidence_policy version 2 and the source_status vocabulary; renders
    use `--progression blue_hour` (stable internal ID; display title
    F-minor Dub Study) for the engine-row sidecar contract. `STUDIO/replicate/test/rg69_defaults_test.rb` pins RG-69
    markup defaults. RG-69 preset names nod to artists but the loops are
    generic genre studies — sourced artist material lives only in
    `recovered_music.json`.

## Session survival

14. Sandbox recycles kill running processes and wipe clones
    (`pub5/`, `pub/`, ...) and `/home/z/.venv` installs. What survives:
    `scripts/`, `patches/`, `download/`, `upload/`, the workspace
    auto-git, and `/home/z/my-project/tools/`. Re-clone with
    `git clone --filter=blob:none` (never shallow) for history mining.
    `pub1` does not exist — the repo is `pub`.
15. Root is unavailable in fresh sessions (sudo asks for a password).
    Local Ruby 3.3 is pre-extracted at `tools/ruby/` (use the `ruby`
    wrapper). Python tooling lives in `/home/z/.venv` and may need
    reinstalling; install CPU-only torch for demucs
    (`--index-url https://download.pytorch.org/whl/cpu`) or the CUDA
    wheels will fill the disk.
