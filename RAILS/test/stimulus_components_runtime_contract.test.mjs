import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { resolve } from "node:path"
import test from "node:test"

const ROOT = resolve(import.meta.dirname, "..")
const VENDOR = resolve(ROOT, "__shared/vendor/javascript")

const readVendor = (name) => readFile(resolve(VENDOR, name), "utf8")
const readSource = (relative) => readFile(resolve(ROOT, relative), "utf8")

test("heavy components stay self-contained and local", async () => {
  const sources = await Promise.all([
    readVendor("@stimulus-components--carousel.js"),
    readVendor("@stimulus-components--chartjs.js"),
    readVendor("@stimulus-components--color-picker.js"),
  ])
  for (const source of sources) {
    assert.match(source, /@hotwired\/stimulus/)
    // The bar is on third-party runtime imports and remote references, not on
    // a local adapter's property name: the carousel keeps the upstream API
    // surface (this.swiper.slideNext) over a scroll-snap implementation.
    assert.doesNotMatch(
      source,
      /from ["'](swiper|chart\.js|@simonwep\/pickr)["']|require\(["'](swiper|chart\.js|@simonwep\/pickr)["']\)|https?:\/\//,
    )
  }
})

test("carousel exposes the component surface without third-party runtime", async () => {
  const source = await readVendor("@stimulus-components--carousel.js")
  assert.match(source, /static values\s*=\s*\{\s*options\s*:\s*Object\s*\}/)
  assert.match(source, /this\.swiper/)
  assert.match(source, /slideNext/)
  assert.match(source, /slidePrev/)
  assert.match(source, /update/)
  assert.match(source, /destroy/)
  assert.match(source, /defaultOptions/)
})

test("chartjs exposes a canvas chart surface without Chart.js", async () => {
  const source = await readVendor("@stimulus-components--chartjs.js")
  assert.match(source, /static targets\s*=\s*\[\s*"canvas"\s*\]/)
  assert.match(source, /static values\s*=\s*\{\s*type:/)
  assert.match(source, /data\s*:\s*Object/)
  assert.match(source, /this\.chart/)
  assert.match(source, /update/)
  assert.match(source, /destroyChart/)
})

test("color picker exposes the picker lifecycle without Pickr", async () => {
  const source = await readVendor("@stimulus-components--color-picker.js")
  assert.match(source, /static targets\s*=\s*\[\s*"button"\s*,\s*"input"\s*\]/)
  assert.match(source, /this\.picker/)
  assert.match(source, /setColor/)
  assert.match(source, /show/)
  assert.match(source, /hide/)
  assert.match(source, /destroy/)
  assert.match(source, /swatches/)
})

test("Amber analytics mounts animated number on real metrics", async () => {
  const source = await readSource("amber/app/views/wardrobe_items/analytics.html.erb")
  assert.equal((source.match(/data-controller="animated-number"/g) || []).length, 3)
  assert.match(source, /data-animated-number-end-value="<%= @analytics\[:total_items\] %>"/)
  assert.match(source, /data-animated-number-end-value="<%= @analytics\[:active_items\] %>"/)
  assert.match(source, /data-animated-number-end-value="<%= @analytics\[:never_worn\] %>"/)
})

test("the timeago adapter keeps the canonical week duration and a real consumer", async () => {
  const source = await readVendor("@stimulus-components--timeago.js")
  assert.match(source, /\["week",604800000\]/)
  assert.doesNotMatch(source, /\["week",6048000000\]/)

  const reports = await readSource("brgen/app/views/admin/reports/index.html.erb")
  assert.match(reports, /data-controller="timeago"/)
  assert.match(reports, /data-timeago-refresh-interval-value="60000"/)
})

test("live search waits for IME input and cancels stale debounced submissions", async () => {
  const source = await readSource("__shared/frontend/live_search_controller.js")
  // Substitute only the Stimulus base class; execute the shipped methods.
  const { default: LiveSearch } = await import("data:text/javascript," +
    encodeURIComponent(source.replace(/^import .*$/m, "class Controller {}")))
  const controller = new LiveSearch()
  let sends = 0
  const input = {}
  controller.hasInputTarget = true
  controller.inputTarget = input
  controller.delayValue = 1
  controller.submitForm = () => { sends += 1; controller.cancelPending() }
  controller.connect()

  controller.input({ isComposing: true })
  assert.equal(controller.timeout, null)
  controller.input({ isComposing: false })
  assert.notEqual(controller.timeout, null)
  controller.cancelPending() // manual Enter or form submission
  controller.filter({ target: input }) // search field blur is not a filter change
  await new Promise(resolve => setTimeout(resolve, 10))
  assert.equal(sends, 0)

  controller.input({ isComposing: false })
  await new Promise(resolve => setTimeout(resolve, 10))
  assert.equal(sends, 1)
  controller.filter({ target: {} })
  assert.equal(sends, 2)
  controller.disconnect()
})

test("bottom sheets ignore interactive controls and cancelled drags restore state", async () => {
  const source = await readSource("__shared/frontend/bottom_sheet_controller.js")
  const { default: BottomSheet } = await import("data:text/javascript," +
    encodeURIComponent(source.replace(/^import .*$/m, "class Controller {}")))
  const controller = new BottomSheet()
  const input = { closest: () => ({}) }
  const surface = { closest: () => null }
  const sheet = { dataset: {}, style: {}, contains: () => true }
  let focused = 0
  Object.assign(controller, {
    levelValue: 1, sheetTarget: sheet,
    hasTriggerTarget: true, triggerTarget: { setAttribute() {}, focus() { focused += 1 } }
  })
  globalThis.document = { activeElement: {} }
  controller.connect()
  controller.pointerDown({ target: input, pointerId: 1, clientY: 0 })
  assert.equal(controller.dragging, false)
  controller.pointerDown({ target: surface, pointerId: 1, clientY: 0 })
  controller.pointerMove({ pointerId: 1, clientY: 200 })
  assert.equal(sheet.style.transform, "translateY(100%)")
  controller.pointerCancel({ pointerId: 1 })
  assert.equal(controller.levelValue, 1)
  assert.equal(sheet.style.transform, "translateY(50%)")
  assert.equal(sheet.style.transition, "")
  controller.pointerDown({ target: surface, pointerId: 2, clientY: 200 })
  controller.pointerMove({ pointerId: 2, clientY: 0 })
  controller.close()
  controller.pointerUp({ pointerId: 2, clientY: 0 })
  assert.equal(controller.levelValue, 0)
  assert.equal(controller.dragging, false)
  assert.equal(sheet.style.transform, "translateY(100%)")
  assert.equal(focused, 1)
  controller.open()
  controller.pointerDown({ target: surface, pointerId: 3, clientY: 0 })
  controller.pointerUp({ pointerId: 3, clientY: 100 })
  assert.equal(controller.levelValue, 1)
  delete globalThis.document
})

test("a failed conversation history request leaves manual retry available", async () => {
  const source = await readSource("__shared/frontend/conversation_log_controller.js")
  const { default: ConversationLog } = await import("data:text/javascript," +
    encodeURIComponent(source.replace(/^import .*$/m, "class Controller {}")))
  const controller = new ConversationLog()
  const button = { disabled: false }
  const attributes = new Map()
  Object.assign(controller, {
    historyUrlValue: "/messages?before=42",
    sentinel: {
      querySelector: () => button,
      setAttribute: (key, value) => attributes.set(key, value),
      removeAttribute: key => attributes.delete(key)
    },
    historyObserver: {
      disconnect() {},
      observe() { assert.fail("failed visible sentinel must not automatically retry") }
    }
  })
  const originalFetch = globalThis.fetch
  try {
    globalThis.fetch = async () => ({ ok: false, status: 503 })
    await controller.loadOlder()
    assert.equal(controller.historyUrlValue, "/messages?before=42")
    assert.equal(controller.loadingHistory, false)
    assert.equal(button.disabled, false)
    assert.equal(attributes.has("aria-busy"), false)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("conversation edits and duplicate replacements do not count as unread", async () => {
  const source = await readSource("__shared/frontend/conversation_log_controller.js")
  const { default: ConversationLog } = await import("data:text/javascript," +
    encodeURIComponent(source.replace(/^import .*$/m, "class Controller {}")))
  const controller = new ConversationLog()
  const original = { document: globalThis.document, MutationObserver: globalThis.MutationObserver,
    getComputedStyle: globalThis.getComputedStyle, Node: globalThis.Node }
  const callbacks = []
  const log = {
    children: [], scrollHeight: 1000, scrollTop: 100, clientHeight: 200,
    querySelectorAll: () => [], addEventListener() {}, removeEventListener() {},
    insertAdjacentElement() {}
  }
  const node = (id, senderId) => ({
    id, parentElement: log, nodeType: 1, matches: () => false,
    querySelectorAll: () => [], querySelector: () => ({ dataset: { senderId } })
  })
  try {
    globalThis.MutationObserver = class {
      constructor(callback) { callbacks.push(callback) }
      observe() {}
      disconnect() {}
    }
    globalThis.Node = { ELEMENT_NODE: 1 }
    globalThis.getComputedStyle = () => ({ overflowY: "auto" })
    globalThis.document = {
      addEventListener() {}, removeEventListener() {},
      createElement: () => ({ addEventListener() {}, setAttribute() {}, remove() {} })
    }
    Object.assign(controller, { element: log, viewerIdValue: "self",
      unreadOneValue: "%{count}", unreadOtherValue: "%{count}" })
    controller.connect()
    const edit = node("message_1", "peer")
    callbacks[0]([{ addedNodes: [edit], removedNodes: [node("message_1", "peer")] }])
    assert.equal(controller.unread, 0)
    const fresh = node("message_2", "peer")
    callbacks[0]([{ addedNodes: [fresh, fresh, node("message_3", "self")], removedNodes: [] }])
    assert.equal(controller.unread, 1)
    controller.disconnect()
  } finally {
    for (const [key, value] of Object.entries(original)) {
      if (value === undefined) delete globalThis[key]
      else globalThis[key] = value
    }
  }
})

test("optimistic sends keep a token for an unchanged payload and preserve text without a log", async () => {
  const source = await readSource("__shared/frontend/optimistic_send_controller.js")
  const { default: OptimisticSend } = await import("data:text/javascript," +
    encodeURIComponent(source.replace(/^import .*$/m, "class Controller {}")))
  const controller = new OptimisticSend()
  const field = { value: "hello" }
  const token = { value: "" }
  const parent = { value: "1" }
  const handlers = new Map()
  const originalWindow = globalThis.window
  try {
    globalThis.window = { addEventListener() {}, removeEventListener() {} }
    Object.assign(controller, {
      hasTokenTarget: true, tokenTarget: token,
      element: {
        closest: () => null,
        querySelector: selector => selector.startsWith("textarea") ? field :
          selector.includes("parent_id") ? parent : null,
        addEventListener: (name, fn) => handlers.set(name, fn),
        removeEventListener() {}
      }
    })
    controller.connect()
    const first = token.value
    handlers.get("submit")()
    handlers.get("turbo:submit-start")()
    assert.equal(field.value, "hello")
    handlers.get("turbo:submit-end")({ detail: { success: false } })
    field.value = "changed"
    field.value = "hello"
    handlers.get("submit")()
    assert.equal(token.value, first)
    parent.value = "2"
    handlers.get("submit")()
    assert.notEqual(token.value, first)
    const second = token.value
    handlers.get("turbo:submit-end")({ detail: { success: true } })
    assert.notEqual(token.value, second)
    controller.disconnect()
  } finally {
    if (originalWindow === undefined) delete globalThis.window
    else globalThis.window = originalWindow
  }
})
