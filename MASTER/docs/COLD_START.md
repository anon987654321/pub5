# MASTER cold start

This is the short path from a fresh checkout to a usable CLI, hosted model route,
and rendered RAILS review. The detailed authority remains in
`MASTER/AGENTS.md`, `MASTER/data/soul.yml`, and `MASTER/data/laws.yml`.

## 1. Prepare the checkout

Use the repository's interpreter selector and bootstrap; do not depend on the
system Ruby being new enough:

```sh
MASTER/bin/dev-bootstrap
MASTER/bin/master --self-test
```

The self-test emits JSON. `PASS` means the reported checks completed.
`INCONCLUSIVE` means a capability was not measured, not that it works.
The `llm-completion` row is always inconclusive here because the self-test does
not send a prompt. It is a boot and capability receipt, not an LLM smoke test.

On Android Termux, run `MASTER/bin/master`; it routes through the supported
Ubuntu or Debian PRoot-Distro installer and launches the CLI inside that guest.
Do not run the Ruby runtime directly on the Termux host.

## 2. Start MASTER and inspect the lanes

```sh
MASTER/bin/master
```

At the prompt:

```text
/doctor
/model list
/doctor keyless
```

`/doctor keyless` temporarily removes hosted-provider keys in the doctor
process, forces the anonymous lane policy, and sends a tiny completion through
the ordinary agent/dispatcher path. It reports the answering model and latency.
It restores the process environment afterward. It is an actual POST probe;
a successful model catalogue fetch alone is not proof that a provider answers.

`MASTER_NO_KEYLESS=1` explicitly disables anonymous lanes. For a deliberate
anonymous-only session, `MASTER_FREE_ONLY=1` ignores hosted-provider keys and
keeps subscription CLI sign-ins under their separate policy.

## 3. Install the rendered-check browser

```sh
MASTER/bin/operator browser install
```

This installs the current Stable Chrome for Testing headless shell into the
user's cache, records its executable as `CHROME_PATH` in
`~/.config/master/env`, and keeps the install versioned. It does not install
system packages or change other provider settings. The host needs `unzip` or
`bsdtar`. The installer reports separately whether the binary's launch probe
succeeded; a downloaded binary with missing OS libraries is not reported as a
working browser.

OpenBSD is not a Chrome for Testing target in this installer. Use the host's
native Chromium package there; the rendered checks still use the same
`CHROME_PATH` discovery contract.

## 4. Capture and review RAILS

Start the local app fleet if it is not already running:

```sh
MASTER/bin/operator triangle up
```

A one-page smoke for one app is deliberately small:

```sh
MASTER/bin/operator visual sweep bsdports --one-page
```

It captures one root page at 390px, without dialogs, and prints the exact
artifact directory. The full sweep remains the complete route/width/dialog
capture:

```sh
MASTER/bin/operator visual sweep
MASTER/bin/operator visual review --app brgen,amber --no-open
```

Standing sweep artifacts and review reports live directly under `RAILS/` in
revision-stamped folders. The curated per-page phone review shots are written
as `RAILS/screenshot_<app>_<page>.png`. Generated folders and shots are ignored
by Git; the sweep's `index.json` records its source revision.

The visual review asks the configured review agent. For image-bearing work,
MASTER filters for image-capable lanes first, then applies the dated human
preference order in `MASTER/data/models.yml#vision_families.review_rank`.
That ordering does not grant image capability to a text-only model.

## 5. Run the full repair path

From the interactive prompt:

```text
/fix RAILS
```

The full visual lane still uses the declared app/page/viewport inventory and
the normal checks. The one-page smoke is not a replacement for the full
rendered evidence. If Chrome, app bundles, local app processes, or development
data are unavailable, the run must report the blocked or inconclusive stage
rather than claim a visual pass.

For a read-only source-plus-rendered review, use
`MASTER/bin/operator style-sweep --app brgen,amber`. For source checks only,
add `--source-only`.

## Status vocabulary

`PASS` requires the check's own evidence. `FAIL` means it measured a defect.
`INCONCLUSIVE` means it did not measure the property. A successful boot,
model catalogue, or screenshot capture must not be promoted into a claim that
an LLM answered or that every RAILS surface rendered correctly.
