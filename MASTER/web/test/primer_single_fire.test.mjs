import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

// public/face_primer.js, the primer script chat/index.html.erb loads, run as
// shipped. Autostart, pointerdown, click, touchend and Enter all call go(); the
// `fired` guard is the only thing standing between a double tap and two face
// imports, two primer dismissals and two PRIMER transitions on boot_fsm.
const publicDir = join(dirname(fileURLToPath(import.meta.url)), "..", "public");
const primerSource = readFileSync(join(publicDir, "face_primer.js"), "utf8");

function primerScript() {
  return primerSource;
}

function element(id) {
  const listeners = {};
  const added = [];
  const removed = [];
  return {
    id,
    added,
    removed,
    listeners,
    dataset: {},
    textContent: "",
    tabIndex: 0,
    parentNode: null,
    classList: { add: (name) => added.push(name), remove: (name) => removed.push(name), contains: () => false },
    addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
    setAttribute() {},
    getAttribute: () => null,
    remove() {},
    focus() {},
  };
}

function loadPrimer({ search = "", readyState = "complete" } = {}) {
  const timers = [];
  const transitions = [];
  const primer = element("primer");
  const nodes = { primer, "prompt-form": element("prompt-form"), "ui-status": element("ui-status"), "primer-title": element("primer-title") };
  const windowListeners = {};
  const warnings = [];
  const documentListeners = {};
  let reloads = 0;
  const sandbox = {
    document: {
      readyState,
      addEventListener: (type, fn) => { documentListeners[type] = fn; },
      currentScript: { dataset: { faceModule: "/face.js?v=test" } },
      getElementById: (id) => nodes[id] || null,
      body: { classList: { add() {}, remove() {}, contains: () => false }, dataset: {} },
    },
    location: { search, reload: () => { reloads += 1; } },
    URLSearchParams,
    CustomEvent: class { constructor(type) { this.type = type; } },
    setTimeout: (fn) => { timers.push(fn); return timers.length; },
    clearTimeout() {},
    setInterval: () => 0,
    clearInterval() {},
    addEventListener(type, fn) { (windowListeners[type] ||= []).push(fn); },
    removeEventListener(type, fn) { windowListeners[type] = (windowListeners[type] || []).filter(listener => listener !== fn); },
    console: { warn: (...args) => warnings.push(args) },
    dispatchEvent() { return true; },
    MASTER: { boot: { transition: (phase) => transitions.push(phase) } },
  };
  sandbox.window = sandbox;
  runInContext(primerScript(), createContext(sandbox));
  // Only the autostart timer: the rest are the 8s hint and the 35s watchdog,
  // whose fallback dismisses the primer on purpose when the face never paints.
  const runAutostart = () => timers.shift()();
  return { primer, transitions, runAutostart, sandbox, windowListeners, warnings, documentListeners, timers, nodes, reloads: () => reloads };
}

test("autostart plus every tap event dismisses the primer once", () => {
  const { primer, transitions, runAutostart } = loadPrimer();
  runAutostart();
  for (const type of ["pointerdown", "click", "touchend"]) primer.listeners[type].forEach((fn) => fn({}));

  assert.equal(transitions.filter((p) => p === "PRIMER").length, 1);
  assert.equal(primer.added.filter((c) => c === "gone").length, 1);
});

test("with ?primer=1 the first tap fires and a second tap does nothing", () => {
  const { primer, transitions } = loadPrimer({ search: "?primer=1" });
  assert.equal(transitions.length, 0, "the overlay waits for a tap");

  primer.listeners.pointerdown[0]({});
  primer.listeners.click[0]({});

  assert.equal(transitions.filter((p) => p === "PRIMER").length, 1);
  assert.equal(primer.added.filter((c) => c === "gone").length, 1);
});

test("early activation waits for the parsed shell before importing the face", () => {
  const { runAutostart, documentListeners, transitions, sandbox, primer } = loadPrimer({ readyState: "loading" });
  sandbox.document.readyState = "interactive";
  runAutostart();
  assert.deepEqual(transitions, ["PRIMER"]);
  assert.equal(sandbox.__MASTER_FACE_IMPORT__, undefined);
  assert.equal(primer.added.includes("gone"), false);
  documentListeners.DOMContentLoaded();
  assert.deepEqual(transitions, ["PRIMER", "ASSETS"]);
  assert.equal(sandbox.__MASTER_FACE_IMPORT__, true);
});

test("a missing painted frame exposes the existing primer as a reload control", () => {
  const { runAutostart, timers, primer, nodes, transitions, reloads } = loadPrimer();
  runAutostart();
  timers[1](); // 35s watchdog, without a face-ready signal.
  assert.equal(transitions.at(-1), "ERROR");
  assert.ok(primer.removed.includes("gone"));
  assert.equal(primer.tabIndex, 0);
  assert.match(nodes["primer-title"].textContent, /face failed to load/);
  primer.listeners.click.forEach(fn => fn({}));
  assert.equal(reloads(), 1);
});

test("audio gesture rejection is reported and a later gesture can recover", async () => {
  const { sandbox, windowListeners, warnings } = loadPrimer();
  let attempts = 0;
  let release;
  const ctx = {
    state: "suspended",
    resume() {
      attempts += 1;
      if (attempts === 1) return Promise.reject(new Error("gesture denied"));
      return new Promise(resolve => { release = () => { this.state = "running"; resolve(); }; });
    }
  };
  sandbox.__MASTER_AUDIO_PRIME__ = ctx;
  const settle = () => new Promise(resolve => setImmediate(resolve));
  windowListeners.pointerdown[0]();
  await settle();
  assert.equal(warnings.length, 1);
  assert.equal(windowListeners.pointerdown.length, 1);
  windowListeners.pointerdown[0]();
  windowListeners.touchend[0]();
  assert.equal(attempts, 2);
  release();
  await settle();
  assert.equal(windowListeners.pointerdown.length, 0);
  assert.equal(windowListeners.touchend.length, 0);
});
