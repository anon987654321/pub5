import assert from "node:assert/strict"
import { mkdtemp, readFile, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

// The shared draft-store controller's snapshot, with Stimulus and idb-keyval
// replaced by stand-ins. A draft is restored into a later page whose form has
// its own CSRF token; carrying the saved one back would replace it with a
// token from another page, so the snapshot leaves it out.

const controllerPath = "../__shared/frontend/draft_store_controller.js"
const source = await readFile(new URL(controllerPath, import.meta.url), "utf8")
const loadable = source
  .replace(/^import \{ Controller \}.*$/m, "class Controller {}")
  .replace(/^import \{ get, set, del \}.*$/m, `const stores = new Map()
const get = async (key, store) => stores.get(store + ":" + key)
const set = async (key, value, store) => stores.set(store + ":" + key, value)
const del = async (key, store) => stores.delete(store + ":" + key)
export { get, set, del }`)
const dir = await mkdtemp(join(tmpdir(), "draft-store-"))
const file = join(dir, "draft_store_controller.mjs")
await writeFile(file, loadable)
const { default: DraftStore, get, set } = await import(pathToFileURL(file).href)

test("a draft keeps what was written and leaves the CSRF token behind", () => {
  const controller = new DraftStore()
  controller.element = {
    querySelectorAll: () => [
      { name: "authenticity_token", type: "hidden", value: "old-token" },
      { name: "post[content]", type: "textarea", value: "Hei Bergen" },
      { name: "post[image]", type: "file", value: "" },
    ],
  }

  assert.deepEqual(controller.snapshot(), { "post[content]": "Hei Bergen" })
})

function draft(key, pwa = false) {
  const controller = new DraftStore()
  const input = { name: "post[content]", type: "textarea", value: "Hei Bergen" }
  const listeners = new Map()
  controller.keyValue = key
  controller.element = {
    querySelectorAll: () => [input],
    matches: () => pwa,
    addEventListener: (name, handler) => listeners.set(name, handler),
    removeEventListener: (name) => listeners.delete(name),
    action: "https://brgen.no/posts",
    method: "post",
  }
  globalThis.window = { addEventListener() {}, removeEventListener() {} }
  controller.connect()
  return { controller, input, listeners }
}

test("online submission retains the draft until confirmed success", async () => {
  Object.defineProperty(globalThis.navigator, "onLine", { value: true, configurable: true })
  const { controller, listeners } = draft("online")
  await controller.handleSubmit({ preventDefault() { assert.fail("online submit was cancelled") } })

  assert.equal((await get("online", "entries"))["post[content]"], "Hei Bergen")
  listeners.get("turbo:submit-end")({ detail: { success: false } })
  assert.equal((await get("online", "entries"))["post[content]"], "Hei Bergen")
  listeners.get("turbo:submit-end")({ detail: { success: true } })
  await controller.pendingSave
  assert.equal(await get("online", "entries"), undefined)
  controller.disconnect()
})

test("PWA forms do not write a second offline queue", async () => {
  Object.defineProperty(globalThis.navigator, "onLine", { value: false, configurable: true })
  const { controller, listeners } = draft("offline", true)
  await controller.handleSubmit({ preventDefault() { assert.fail("draft controller owns no PWA submission") } })
  assert.equal(await get("offline", "queue"), undefined)
  assert.equal((await get("offline", "entries"))["post[content]"], "Hei Bergen")
  listeners.get("pub5:offline-queued")()
  await controller.pendingSave
  assert.equal(await get("offline", "entries"), undefined)
  controller.disconnect()
})

test("a newer edit survives acknowledgement of an older submission", async () => {
  Object.defineProperty(globalThis.navigator, "onLine", { value: true, configurable: true })
  const { controller, input, listeners } = draft("newer")
  await controller.handleSubmit({})
  input.value = "Ny tekst"
  controller.scheduleSave()
  listeners.get("turbo:submit-end")({ detail: { success: true } })
  await controller.save()
  assert.equal((await get("newer", "entries"))["post[content]"], "Ny tekst")
  controller.disconnect()
})

test("an HTTP error does not discard a queued submission", async () => {
  const { controller } = draft("retry")
  const queued = { action: controller.element.action, method: "post", payload: { "post[content]": "Hei" } }
  await set("retry", [queued], "queue")
  globalThis.fetch = async () => ({ ok: false, status: 503 })
  await controller.flushQueue()
  assert.deepEqual(await get("retry", "queue"), [queued])
  controller.disconnect()
})
