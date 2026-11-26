import { Controller } from "@hotwired/stimulus"
import { get, set, del } from "idb-keyval"

const STORE = "autosave"

export default class extends Controller {
  static values = {
    key: String,
    url: String,
    interval: { type: Number, default: 5000 },
    saving: { type: String, default: "Saving…" },
    saved: { type: String, default: "Saved" },
    savedLocally: { type: String, default: "Saved locally" },
    restored: { type: String, default: "Restored" },
    failed: { type: String, default: "Not saved" }
  }

  static targets = ["status"]

  connect() {
    this.dirty = false
    this.revision = (this.revision || 0) + 1
    this.active = true
    this.onSubmitStart = () => { this.submittedRevision = this.revision }
    this.onSubmitEnd = (event) => {
      if (event.detail?.success === true) this.clearSubmitted()
    }
    this.element.addEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
    this.onInput = this.markDirty.bind(this)
    this.onOnline = this.flush.bind(this)
    this.element.addEventListener("input", this.onInput)
    this.element.addEventListener("change", this.onInput)
    window.addEventListener("online", this.onOnline)
    // A hidden tab saves once as it is hidden, then waits: the interval runs
    // only while the page is visible, so a backgrounded draft costs no PATCH
    // every few seconds and no wake-ups on a phone.
    this.onVisibility = () => (document.hidden ? this.pause() : this.resume())
    document.addEventListener("visibilitychange", this.onVisibility)
    if (!document.hidden) this.resume()
    this.restore()
  }

  disconnect() {
    this.active = false
    this.element.removeEventListener("turbo:submit-start", this.onSubmitStart)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    this.element.removeEventListener("input", this.onInput)
    this.element.removeEventListener("change", this.onInput)
    window.removeEventListener("online", this.onOnline)
    document.removeEventListener("visibilitychange", this.onVisibility)
    this.stopInterval()
  }

  resume() {
    if (this.intervalId) return
    this.intervalId = window.setInterval(() => this.flush(), this.intervalValue)
  }

  pause() {
    this.stopInterval()
    this.flush()
  }

  stopInterval() {
    if (this.intervalId) window.clearInterval(this.intervalId)
    this.intervalId = null
  }

  markDirty() {
    this.revision += 1
    this.dirty = true
    this.setStatus(this.savingValue)
  }

  async restore() {
    const revision = this.revision
    try {
      const saved = await get(this.keyValue, STORE)
      if (!saved || !this.active || revision !== this.revision) return
      // The draft-store saves every keystroke and owns restoration when present.
      if (this.element.dataset.controller?.split(/\s+/).includes("draft-store")) return
      this.applySnapshot(saved)
      this.setStatus(this.restoredValue)
    } catch (error) {
      console.warn("autosave restore:", error)
    }
  }

  flush() {
    if (this.inFlight || !this.dirty) return this.inFlight
    const revision = this.revision
    this.inFlight = this.persist(this.snapshot(), revision)
      .finally(() => { this.inFlight = null })
    return this.inFlight
  }

  async persist(snapshot, revision) {
    const local = await set(this.keyValue, snapshot, STORE)
      .then(() => true).catch(() => false)

    let remote = false
    if (navigator.onLine && this.hasUrlValue) {
      const headers = {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
      }
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers,
        credentials: "same-origin",
        body: new URLSearchParams(snapshot)
      }).catch(() => null)
      remote = response?.ok === true && !response.redirected
    }

    if (revision !== this.revision || !this.active) return
    // Offline writes with a server destination remain dirty for reconnection.
    this.dirty = !(remote || (local && !this.hasUrlValue))
    this.setStatus(remote ? this.savedValue : local ? this.savedLocallyValue : this.failedValue)
  }

  async clearSubmitted() {
    const revision = this.submittedRevision
    if (revision == null || revision !== this.revision) return
    this.dirty = false
    await this.inFlight
    if (revision !== this.revision) return
    this.dirty = false
    try {
      await del(this.keyValue, STORE)
    } catch (error) {
      console.warn("autosave clear:", error)
    }
  }

  snapshot() {
    const fields = {}
    this.element.querySelectorAll("input, textarea, select").forEach(field => {
      if (!field.name || field.disabled || /^(file|password|submit|button|reset)$/i.test(field.type) ||
          /(?:^|[^a-z0-9])(?:password|password_confirmation|token|secret|api_key|private_key|otp|authenticity)(?:$|[^a-z0-9])/i.test(field.name)) return
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

  setStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
  }
}
