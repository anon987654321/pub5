import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runInNewContext } from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dashboard = readFileSync(join(root, "app", "views", "dashboard", "index.html.erb"), "utf8");
const chatIndex = readFileSync(join(root, "app", "views", "chat", "index.html.erb"), "utf8");
const pwaManifest = readFileSync(join(root, "app", "views", "pwa", "manifest.json.erb"), "utf8");
const publicDir = join(root, "public");
const chat = readFileSync(join(publicDir, "chat.js"), "utf8");
// 40_accessibility_motion.css and the sources split out of it, read as one.
const faceMotion = ["40_accessibility_motion.css", "41_print.css", "42_wscons_skin.css", "43_face_chrome.css",
  "44_stipple_playground.css"].map((name) => readFileSync(join(root, "styles", "face", name), "utf8")).join("\n");
const faceChrome = readFileSync(join(root, "styles", "face", "60_session_chrome.css"), "utf8");
const faceBuilder = readFileSync(join(root, "..", "..", "MASTER", "tools", "rails", "build_face_css.rb"), "utf8");
const faceConversation = readFileSync(join(root, "styles", "face", "30_conversation.css"), "utf8");
const manifest = readFileSync(join(root, "config", "face_assets.yml"), "utf8");
const laws = readFileSync(join(root, "..", "..", "MASTER", "data", "laws.yml"), "utf8");
const tokens = readFileSync(join(root, "..", "..", "MASTER", "data", "tokens.yml"), "utf8");
const interaction = readFileSync(join(publicDir, "master_interaction_state.js"), "utf8");
const faceWorld = readFileSync(join(publicDir, "face_world.js"), "utf8");
const audio = readFileSync(join(publicDir, "face_audio_field.js"), "utf8");
const render = readFileSync(join(publicDir, "face_render_policy.js"), "utf8");
const voice = readFileSync(join(publicDir, "voice_surface.js"), "utf8");
const tasks = readFileSync(join(publicDir, "master_task_ui.js"), "utf8");
const workspace = readFileSync(join(publicDir, "master_workspace.js"), "utf8");
const accessibility = readFileSync(join(publicDir, "master_accessibility.js"), "utf8");
const part5 = readFileSync(join(publicDir, "face.part5.txt"), "utf8");
const faceCss = readFileSync(join(publicDir, "face.css"), "utf8");
const runtime = readFileSync(join(publicDir, "face.runtime.js"), "utf8");

test("canonical interface modules are declared in the shell manifest", () => {
  for (const name of [
    "master_interaction_state", "face_audio_field", "face_render_policy",
    "voice_surface", "master_task_ui", "master_workspace", "master_accessibility"
  ]) {
    assert.ok(manifest.split("\n").includes("  - " + name));
  }
});

test("tokens publish the canonical interaction, audio and performance contract", () => {
  assert.match(tokens, /interaction:/);
  assert.match(tokens, /audio:/);
  assert.match(tokens, /target_fps: 60/);
  assert.match(tokens, /main_thread_budget_ms: 8/);
  assert.match(tokens, /speech:start/);
  assert.match(tokens, /task:waiting-human/);
});

test("interaction state defines the canonical turn task tool visual and memory stores", () => {
  for (const name of ["interaction", "turn", "task", "tool", "visual", "memory"]) assert.match(interaction, new RegExp(name + ":"));
  for (const event of [
    "speech:start", "speech:partial", "speech:end", "speech:abort",
    "tts:start", "tts:end", "tts:interrupt",
    "turn:committed", "turn:discarded", "turn:interrupted",
    "task:queued", "task:waiting-human", "task:waiting-network", "task:waiting-model",
    "tool:queued", "tool:active", "tool:retry", "tool:complete", "tool:failed"
  ]) assert.ok((interaction + tokens).includes(event), event + " missing");
});

test("audio field keeps smoothed and transient signals separate", () => {
  for (const field of ["rms", "peak", "bass", "mid", "high", "centroid", "onset", "speechActivity",
                       "sampleRate", "channels", "analyserWindow", "latencyMs", "playbackBufferMs", "underruns"]) {
    assert.ok(audio.includes(field), field + " missing");
  }
  assert.match(audio, /const transientDecay/);
  assert.match(audio, /function ingestMicrophone/);
  assert.match(audio, /function ingestPlayback/);
  assert.match(audio, /audio:update/);
});

test("render policy exposes a 60fps target and adaptive hysteresis without a second RAF", () => {
  assert.match(render, /TARGET_FPS = Number\(PERFORMANCE\.target_fps\) \|\| 60/);
  assert.match(render, /HYSTERESIS/);
  assert.match(render, /function recordFrame/);
  assert.match(render, /PerformanceObserver/);
  assert.doesNotMatch(render, /requestAnimationFrame\(/);
});

test("render quality recovers at the target cap and ignores suspended intervals", () => {
  const listeners = new Map();
  const document = {
    hidden: false,
    documentElement: { dataset: {} },
    createElement: () => ({ getContext: () => null }),
    addEventListener: (name, callback) => listeners.set(name, callback),
  };
  const window = { addEventListener() {}, MASTER_VISUAL_LIMITS: { maxFps: 50 } };
  runInNewContext(render, {
    window, document, navigator: {}, location: { search: "" },
    devicePixelRatio: 1, performance: { mark() {}, now: () => 0 },
    matchMedia: () => ({ matches: false }),
  });
  const policy = window.MasterRenderPolicy;
  for (let time = 0; time <= 1000; time += 40) policy.recordFrame(time);
  assert.equal(policy.snapshot().quality, "reduced");
  for (let time = 1020; time <= 2000; time += 20) policy.recordFrame(time);
  assert.equal(policy.snapshot().quality, "auto");
  assert.equal(policy.snapshot().fps, 50);
  assert.equal(policy.snapshot().transitions, 2);

  document.hidden = true;
  listeners.get("visibilitychange")();
  policy.recordFrame(3000);
  document.hidden = false;
  listeners.get("visibilitychange")();
  policy.recordFrame(12000);
  assert.equal(policy.snapshot().frameMs, 0);
  assert.equal(policy.snapshot().quality, "auto");

  window.MASTER_VISUAL_LIMITS.maxFps = 25;
  for (let time = 12040; time <= 13040; time += 40) policy.recordFrame(time);
  assert.equal(policy.snapshot().fps, 25);
  assert.equal(policy.snapshot().quality, "auto");
});

test("voice surface coordinates typing suspension and explicit recovery", () => {
  assert.match(voice, /enterkeyhint/);
  assert.match(voice, /suspendForTyping/);
  assert.match(voice, /resumeAfterTyping/);
  assert.match(voice, /retry voice/);
});

test("voice projection does not overwrite typed drafts or reuse previous recognition text", () => {
  const events = new Map(), inputEvents = new Map(), formEvents = new Map();
  const node = { value: "typed draft", dataset: {}, setAttribute() {},
    addEventListener: (name, fn) => inputEvents.set(name, fn),
    form: { addEventListener: (name, fn) => formEvents.set(name, fn) } };
  const transcript = { textContent: "" };
  const document = { getElementById: id => id === "prompt-input" ? node : id === "voice-transcript" ? transcript : null };
  const window = { addEventListener: (name, fn) => events.set(name, fn) };
  runInNewContext(voice, { window, document, navigator: {} });
  assert.ok(formEvents.has("submit"));
  events.get("stt:start")();
  events.get("stt:partial")({ detail: { text: "late voice" } });
  assert.equal(node.value, "typed draft");
  assert.equal(node.dataset.voiceDraft, undefined);

  node.value = "";
  events.get("stt:start")();
  events.get("stt:partial")({ detail: { text: "new voice" } });
  assert.equal(node.value, "new voice");
  assert.equal(node.dataset.voiceDraft, "partial");
  node.value = "my edited text";
  inputEvents.get("input")();
  events.get("stt:end")({ detail: { text: "old voice" } });
  assert.equal(node.value, "my edited text");
  assert.equal(node.dataset.voiceDraft, undefined);

  events.get("stt:abort")();
  node.value = "";
  events.get("stt:start")();
  events.get("stt:end")({ detail: {} });
  assert.equal(node.value, "");
  assert.equal(window.MASTER_VOICE_SURFACE.lastVoiceText(), "");
});

test("task and workspace projections expose stable IDs and provenance", () => {
  assert.match(tasks, /taskCreate/);
  assert.match(tasks, /provenance/);
  assert.match(tasks, /waiting for you/);
  assert.match(tasks, /retry/);
  assert.match(workspace, /version:/);
  assert.match(workspace, /provenance/);
  assert.match(workspace, /relationships/);
  assert.match(workspace, /select\(/);
  assert.match(workspace, /master:workspace:v1/);
});

test("accessibility projection exposes live state, reduced motion and forced colours", () => {
  assert.match(accessibility, /aria-live/);
  assert.match(accessibility, /prefers-reduced-motion/);
  assert.match(accessibility, /forced-colors/);
  assert.match(accessibility, /microphone/);
  assert.match(accessibility, /aria-pressed/);
  assert.match(accessibility, /state === "listening" \? "true" : "false"/);
  assert.match(accessibility, /task failed/);
  assert.match(faceCss, /#cmd-palette-input:focus-visible/);
});

test("recognizer end is not treated as a conversational boundary", () => {
  assert.match(part5, /orphanedTranscript = sttPartial\.trim\(\)/);
  assert.match(part5, /Browser onend is an implementation boundary/);
  assert.match(part5, /new CustomEvent\('stt:partial'/);
  assert.match(part5, /new CustomEvent\('stt:end'/);
  assert.match(part5, /commitTurn\?\.\(t2, 'voice'/);
});

test("generated face runtime names current face sources", () => {
  for (const file of ["face.part1.txt", "face.part2.txt", "face.part3.txt", "face_speech_runtime.js", "face_speech_playback.js", "face.part5.txt"]) {
    const escaped = file.replace(".", "\\.");
    assert.match(runtime, new RegExp(escaped + "\\b"), file + " is not named by face.runtime.js");
  }
});

test("virtualized chat retains recoverable older messages", () => {
  assert.match(chat, /const CHAT_ARCHIVE_BATCH = 28;/);
  assert.match(chat, /function restoreOlderChatMessages\(\)/);
  assert.match(chat, /chatArchive\.splice\(start\)/);
  assert.match(chat, /chatT\('load_older_messages'/);
  assert.doesNotMatch(chat, /chatArchived \* 68/);
  assert.match(faceMotion, /\.virtual-spacer-load/);
  assert.match(faceCss, /\.virtual-spacer-load/);
});
test("message action menu is localized, safe to render, and viewport-aware", () => {
  const start = chat.indexOf("function openActionMenu(msgEl)");
  const end = chat.indexOf("// Per-message context-usage footer", start);
  const menu = chat.slice(start, end);
  assert.ok(start >= 0 && end > start, "openActionMenu function is missing");
  for (const key of ["message_actions", "message_copy", "message_quote", "message_simpler", "message_deeper"]) {
    assert.match(menu, new RegExp("chatT\\('" + key + "'"));
  }
  assert.match(menu, /visualViewport/);
  assert.match(menu, /setAttribute\('role', 'group'\)/);
  assert.match(menu, /menu\.querySelector\('button'\)\?\.focus/);
  assert.match(menu, /e\.key === 'Escape'/);
  assert.match(menu, /removeEventListener\('keydown', close\)/);
  assert.match(menu, /activeChatActionMenuDismiss\?\.\(\)/);
  assert.match(menu, /activeChatActionMenuDismiss === dismiss/);
  assert.doesNotMatch(menu, /menu\.innerHTML/);
  for (const css of [faceConversation, faceCss]) {
    assert.match(css, /\.action-menu button\s*\{[^}]*min-block-size:\s*var\(--tap-min\)/s);
    assert.match(css, /\.action-menu button:focus-visible\s*\{[^}]*outline:/s);
  }
});
test("face shell stays flat and square", () => {
  // The lookahead sits before the whitespace so "backdrop-filter: none;" cannot
  // slip past it by backtracking \s*.
  assert.doesNotMatch(faceCss, /backdrop-filter\s*:(?!\s*none\b)[^;]+;/i);
  assert.doesNotMatch(faceCss, /filter\s*:\s*[^;]*\b(?:blur|drop-shadow)\(/i);

  const pip = faceCss.match(/body\[data-face-pip="1"\] canvas\s*\{[^}]+\}/);
  assert.ok(pip, "PIP face canvas rule is missing");
  assert.match(pip[0], /border-radius:\s*0;/);

  const rail = faceCss.match(/\.master-task-rail\s*\{[^}]+\}/);
  assert.ok(rail, "task rail rule is missing");
  assert.match(rail[0], /background:\s*var\(--face-bg\);/);
});

test("FaceWorld reports one performance sample per canonical update", () => {
  const world = readFileSync(join(publicDir, "face_world.js"), "utf8");
  assert.match(world, /MasterRenderPolicy\?\.recordFrame\?\.\(now\)/);
});

test("evidence events retain their event name and reach the shared FaceWorld clock", () => {
  assert.ok(tokens.includes("- memory:added"), "memory:added must be allowed by the canonical contract");
  assert.match(tokens, /task_ring:\n\s+enabled: true/);
  assert.match(interaction, /const detail = \{ \.\.\.payload, ts: now\(\), type: name \}/);
  assert.match(interaction, /detail\.recordType = payload\.type/);
  for (const event of ["task:queued", "task:active", "task:waiting-human", "task:complete",
                       "task:failed", "tool:queued", "tool:active", "tool:complete", "tool:failed",
                       "memory:added"]) {
    assert.ok(tokens.includes("- " + event), event + " is missing from the face contract");
  }
  assert.match(faceWorld, /function syncActivitySnapshot\(\)/);
  assert.match(faceWorld, /function updateActivityNodes\(now, state, reducedMotion = false\)/);
  assert.match(faceWorld, /updateActivityNodes\(now, state, reducedMotion\)/);
  assert.doesNotMatch(faceWorld, /requestAnimationFrame\(/);
  assert.ok(manifest.includes("- face_world.js"), "spatial nodes must use the already loaded FaceWorld asset");
});

test("mission control distinguishes fresh, failed and terminal live states", () => {
  // The view owns the status node and localized strings; dashboard_live.js polls.
  const poller = readFileSync(join(publicDir, "dashboard_live.js"), "utf8");
  assert.match(dashboard, /id: "refresh-state", role: "status"/);
  assert.match(dashboard, /data-i18n-refresh-failed=/);
  assert.match(dashboard, /data-i18n-updated=/);
  assert.match(dashboard, /<script src="<%= asset_path\("dashboard_live\.js"\) %>"/);
  assert.match(poller, /if \(!r\.ok \|\| d\.error\)/);
  assert.match(poller, /catch \(error\)/);
  assert.match(poller, /document\.hidden/);
  assert.match(poller, /inFlight/);
  assert.match(poller, /i18nRefreshFailed/);
  assert.match(poller, /i18nUpdated/);
  assert.match(poller, /closeDoor\(\)/);
});

test("MASTER web keeps the face and mission surface free of workspace tabs", () => {
  for (const page of [chatIndex, dashboard]) {
    assert.match(page, /class="[^"]*\bmaster-titlebar\b/);
    assert.doesNotMatch(page, /master-session-tabs|master-session-tab/);
  }
  assert.match(chatIndex, /class="prompt-sigil"[^>]*><%= Master::Face::Contract\.shell_prompt %>/);
  assert.match(faceChrome, /#prompt-form \.prompt-sigil/);
});

test("MASTER's first screen is its pixel face, readable CLI and Brgen wordmark", () => {
  assert.match(chatIndex, /<% mark = "ai\.brgen\.no" %>/);
  assert.match(chatIndex, /aria-label="<%= mark %>"/);
  assert.match(chatIndex, /<span class="brand-text"><%= mark %><\/span>/);
  assert.match(dashboard, /aria-label="ai\.brgen\.no"/);
  assert.match(dashboard, /<span class="brand-text">ai\.brgen\.no<\/span>/);
  assert.match(faceCss, /--font-logo: "Helvetica Neue", Helvetica, Arial, sans-serif;/);
  assert.match(faceCss, /font: 700 clamp\(0\.9375rem, 2\.8vw, 1\.125rem\) \/ 1 var\(--font-logo\)/);
  assert.match(faceCss, /--terminal-font-size: 1\.25rem/);
  assert.match(faceCss, /font: var\(--terminal-font-size\)\/var\(--leading-body\) var\(--font-mono\)/);
  assert.match(faceCss, /font: 400 var\(--terminal-font-size\)\/var\(--leading-body\) var\(--font-mono\)/);
  assert.match(faceChrome, /\.master-titlebar \.brand-mark \{[\s\S]*?display: inline-flex/);
  assert.match(faceMotion, /\.brand-mark \{[\s\S]*?font: 700/);
});

test("canonical theme token reaches CSS, routes and PWA manifest", () => {
  const rootStart = faceCss.indexOf("/* BEGIN:generated-face-root");
  const rootEnd = faceCss.indexOf("/* END:generated-face-root */", rootStart);
  assert.ok(rootStart >= 0 && rootEnd > rootStart, "generated face token block is missing");
  const root = faceCss.slice(rootStart, rootEnd);
  // face_root.palette reads brgen's family tokens; anchors keep the older tinted values.
  assert.match(tokens, /face_bg: "#000000"/);
  assert.doesNotMatch(tokens, /x_text/);
  assert.match(root, /--face-bg: #000000;/);
  assert.match(root, /--face-fg: var\(--c-text\);/);
  // raw keeps ActionView from HTML-escaping the JSON string's quotes.
  assert.match(pwaManifest, /"background_color": <%= raw theme_color\.to_json %>/);
  assert.match(pwaManifest, /"theme_color": <%= raw theme_color\.to_json %>/);
  for (const page of [chatIndex, dashboard]) {
    assert.match(page, /theme_color = Master\.tokens\.fetch\("face_root"\)\.fetch\("face_bg"\)/);
    assert.match(page, /meta name="theme-color" content="<%= theme_color %>"/);
  }
  assert.match(dashboard, /rel="manifest" href="<%= pwa_manifest_path\(format: :json\) %>"/);
  assert.doesNotMatch(faceMotion, /--c-accent: oklch\(82% 0\.12 222\)/);
  assert.doesNotMatch(faceMotion, /--radius-medium: 12px/);
});

test("session chrome is mobile-first, nuanced, flat and touch-ready", () => {
  assert.ok(faceChrome.includes("background: var(--chrome-band)"));
  assert.ok(faceChrome.includes("background: var(--chrome-surface-active)"));
  assert.ok(faceChrome.includes("outline: 2px solid var(--chrome-focus)"));
  assert.doesNotMatch(faceChrome, /master-session-tabs|master-session-tab/);
  assert.ok(faceChrome.includes("var(--safe-left)"));
  assert.ok(faceChrome.includes("var(--safe-bottom)"));
  assert.ok(faceChrome.includes("min-block-size: var(--tap-min)"));
  assert.match(faceChrome, /@media \(min-width: 480px\)/);
  assert.match(faceChrome, /prefers-reduced-motion/);
  assert.match(faceChrome, /prefers-reduced-transparency/);
  assert.match(faceChrome, /forced-colors/);
  assert.doesNotMatch(faceChrome, /@media \(max-width:/);
  assert.doesNotMatch(faceChrome, /backdrop-filter\s*:/);
  assert.doesNotMatch(faceChrome, /box-shadow\s*:/);
  assert.doesNotMatch(faceChrome, /border-radius:\s*(?:[1-9]\d*|\d*\.\d+)(?:px|rem|em|%)?/);
  assert.doesNotMatch(faceChrome, /border-(?:block|inline)-end:\s*1px/);
});

test("history drawer clears the session prompt and keyboard", () => {
  assert.match(faceConversation, /#chat-history-panel \{[^}]*bottom: calc\(76px \+ var\(--safe-bottom\) \+ var\(--keyboard-inset, 0px\)\);/);
  assert.ok(faceChrome.includes("#chat-history-panel { bottom: calc(80px + var(--safe-bottom) + var(--keyboard-inset, 0px)); }"));
  assert.match(faceCss, /#chat-history-panel \{[^}]*bottom: calc\(76px \+ var\(--safe-bottom\) \+ var\(--keyboard-inset, 0px\)\);/);
  assert.ok(faceCss.includes("#chat-history-panel { bottom: calc(80px + var(--safe-bottom) + var(--keyboard-inset, 0px)); }"));
});

test("served face.css is generated from the ordered editable sources", () => {
  // Two generated blocks follow the base module: brgen's family tokens, then the face root.
  const rootStart = faceCss.indexOf("/* BEGIN:generated-family-tokens");
  const rootMarker = "/* END:generated-face-root */";
  const rootEnd = faceCss.indexOf(rootMarker, rootStart);
  assert.ok(rootStart >= 0 && rootEnd >= 0, "generated token block is missing");
  const rootBlock = faceCss.slice(rootStart, rootEnd + rootMarker.length);
  const partsBlock = faceBuilder.match(/PARTS = %w\[([\s\S]*?)\]/);
  assert.ok(partsBlock, "stylesheet builder source list is missing");
  const parts = partsBlock[1].trim().split(/\s+/);
  assert.ok(parts.includes("60_session_chrome.css"), "session chrome must be in the generated source order");
  const expected = readFileSync(join(root, "styles", "face", parts[0]), "utf8")
    + rootBlock
    + parts.slice(1).map(name => readFileSync(join(root, "styles", "face", name), "utf8")).join("");
  assert.equal(faceCss, expected, "public/face.css drifted from its authoritative source modules");
});

test("face and terminal occupy separate regions and the terminal uses local Geist Mono", () => {
  assert.match(chatIndex, /<div id="face-region">\s*<canvas id="cognition-ecology"[\s\S]*?<canvas id="face"[\s\S]*?<\/div>/);
  assert.ok(chatIndex.indexOf('id="face-region"') < chatIndex.indexOf('id="chat-shell"'));
  assert.match(faceChrome, /#face-region\s*\{[\s\S]*?block-size: var\(--face-region-height\)/);
  assert.match(faceChrome, /#chat-shell\s*\{\s*inset: var\(--terminal-region-top\)/);
  assert.match(faceCss, /--font-mono: "Geist Mono", "JetBrainsMono Nerd Font"/);
  assert.match(faceCss, /url\("\/fonts\/GeistMono-Variable\.woff2"\)/);
});

test("terminal retains decoded source text without re-escaping it", () => {
  assert.match(chat, /const text = previousText \+ String\(raw\)/);
  assert.ok(chat.indexOf("const nearBottom = log.scrollHeight", chat.indexOf("const previousText = terminalSource")) <
    chat.indexOf("if (text.includes", chat.indexOf("const previousText = terminalSource")));
});

test("browser chrome is measured, not simulated, and operator commands are absent", () => {
  assert.match(chatIndex, /window\.MASTER_COMMANDS = \[\]/);
  assert.match(chatIndex, /id="battery-indicator" role="img" hidden/);
  assert.match(chat, /typeof navigator\.getBattery !== 'function'/);
  assert.match(chat, /battery\.addEventListener\('levelchange'/);
  assert.match(chat, /const commandHistory = \[\]/);
  assert.match(chat, /historyIndex === commandHistory\.length \? historyDraft/);
});
