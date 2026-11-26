import { Controller } from "@hotwired/stimulus"
import { get, set, del } from "idb-keyval"

const STORE = "entries"
const QUEUE = "queue"

export default class extends Controller {
  static values = { key: String }

  connect() {
    this.saveTimer = null
    this.revision = 0
    this.pendingSave = Promise.resolve()
    this.onInput = this.scheduleSave.bind(this)
    this.onOnline = this.flushQueue.bind(this)
    this.onSubmit = this.handleSubmit.bind(this)
    this.onSubmitEnd = (event) => {
      if (event.detail?.success === true) this.clearSubmitted()
    }
    this.onQueued = () => this.clearSubmitted()
    this.element.addEventListener("input", this.onInput)
    this.element.addEventListener("change", this.onInput)
    this.element.addEventListener("submit", this.onSubmit)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
    this.element.addEventListener("pub5:offline-queued", this.onQueued)
    window.addEventListener("online", this.onOnline)
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("input", this.onInput)
    this.element.removeEventListener("change", this.onInput)
    this.element.removeEventListener("submit", this.onSubmit)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    this.element.removeEventListener("pub5:offline-queued", this.onQueued)
    window.removeEventListener("online", this.onOnline)
    if (this.saveTimer) clearTimeout(this.saveTimer)
  }

  async handleSubmit(event) {
    const payload = this.snapshot()
    this.submittedRevision = this.revision
    clearTimeout(this.saveTimer)
    const saved = this.save(payload)

    // The canonical PWA runtime owns offline submissions from marked forms.
    // A second queued POST here would replay the same draft twice.
    if (navigator.onLine || this.element.matches("form[data-pwa-offline]")) {
      await saved
      return
    }

    event.preventDefault()
    await saved
    await this.enqueue(payload)
    await this.registerSync()
  }

  scheduleSave() {
    this.revision += 1
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(), 150)
  }

  async restore() {
    const revision = this.revision
    const saved = await get(this.keyValue, STORE)
    if (!saved || revision !== this.revision) return
    this.applySnapshot(saved)
  }

  save(payload = this.snapshot()) {
    this.pendingSave = this.pendingSave.then(() => set(this.keyValue, payload, STORE))
      .catch(error => console.warn("draft-store save:", error))
    return this.pendingSave
  }

  clearSubmitted() {
    const revision = this.submittedRevision
    if (revision == null || revision !== this.revision) return this.pendingSave

    this.submittedRevision = null
    clearTimeout(this.saveTimer)
    // An earlier save must finish first; a newer edit must never be erased.
    this.pendingSave = this.pendingSave.then(() => {
      if (revision === this.revision) return del(this.keyValue, STORE)
    }).catch(error => console.warn("draft-store clear:", error))
    return this.pendingSave
  }

  snapshot() {
    const fields = {}
    this.element.querySelectorAll("input, textarea, select").forEach(field => {
      if (!field.name || field.type === "file" || field.name === "authenticity_token") return
      if (field.type === "checkbox") {
        fields[field.name] = field.checked ? "1" : "0"
        return
      }
      if (field.type === "radio") {
        if (field.checked) fields[field.name] = field.value
        return
      }
      fields[field.name] = field.value
    })
    return fields
  }

  applySnapshot(snapshot) {
    Object.entries(snapshot || {}).forEach(([name, value]) => {
      const fields = this.element.querySelectorAll(`[name="${CSS.escape(name)}"]`)
      fields.forEach(field => {
        if (field.type === "checkbox") field.checked = value === "1"
        else if (field.type === "radio") field.checked = field.value === value
        else field.value = value
      })
    })
  }

  async enqueue(payload) {
    const queue = (await get(this.keyValue, QUEUE)) || []
    queue.push({
      payload,
      queuedAt: Date.now(),
      action: this.element.action,
      method: this.element.method || "post",
      csrfToken: this.csrfToken()
    })
    await set(this.keyValue, queue, QUEUE)
  }

  async flushQueue() {
    const queue = (await get(this.keyValue, QUEUE)) || []
    if (!queue.length) return

    const remaining = []
    for (const entry of queue) {
      try {
        const response = await fetch(entry.action, {
          method: entry.method.toUpperCase(),
          credentials: "same-origin",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "X-CSRF-Token": entry.csrfToken || ""
          },
          body: new URLSearchParams(entry.payload)
        })
        if (!response.ok) remaining.push(entry)
      } catch (_error) {
        remaining.push(entry)
      }
    }

    await set(this.keyValue, remaining, QUEUE)
    // A queued submission is not necessarily the newest local draft.
    if (!remaining.length) await del(this.keyValue, QUEUE)
  }

  async registerSync() {
    if (!("serviceWorker" in navigator) || !("SyncManager" in window)) return
    const reg = await navigator.serviceWorker.ready
    await reg.sync.register("draft-store").catch(() => {})
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
