import { Controller } from "@hotwired/stimulus"

// Heartbeat so the room knows who still has it open.
//
// Push-capable browsers lease their own endpoint. A web push is suppressed only
// for the browser that has this conversation open; the reader's phone and other
// browsers can still notify. Readers without a push subscription retain the
// ordinary user-level presence heartbeat.
const BEAT_MS = 20_000

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue) return

    this.stopped = false
    this.paused = document.hidden
    this.ready = true
    this.left = true
    this.endpoint = null

    this.onVisibility = () => {
      if (document.hidden) {
        this.paused = true
        this.#leave()
      } else {
        this.paused = false
        this.#start()
      }
    }
    document.addEventListener("visibilitychange", this.onVisibility)

    // Leave promptly rather than waiting out the TTL. keepalive lets the request
    // outlive the page; pagehide fires on mobile background/close where unload
    // does not.
    this.onLeave = () => {
      this.paused = true
      this.#leave()
    }
    window.addEventListener("pagehide", this.onLeave)
    document.addEventListener("turbo:before-visit", this.onLeave)

    // Start ordinary presence immediately; waiting for a service-worker
    // registration must never make the conversation appear closed.
    this.#start()
    this.#resolveEndpoint().then(endpoint => {
      if (this.stopped) return
      this.endpoint = endpoint
      if (endpoint && !this.paused && !document.hidden && !this.left) this.#beat()
    })
  }

  disconnect() {
    this.stopped = true
    this.paused = true
    this.#stopTimer()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.onLeave)
    document.removeEventListener("turbo:before-visit", this.onLeave)
    this.#leave()
  }

  #resolveEndpoint() {
    if (!("serviceWorker" in navigator)) return Promise.resolve(null)

    return navigator.serviceWorker.ready
      .then(registration => registration.pushManager?.getSubscription())
      .then(subscription => subscription?.endpoint || null)
      .catch(() => null)
  }

  #start() {
    if (this.stopped || this.paused || !this.ready || document.hidden || this.timer) return

    this.left = false
    this.#beat()
    this.timer = setInterval(() => this.#beat(), BEAT_MS)
  }

  #stopTimer() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  #token() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  #payload() {
    return this.endpoint ? { device_type: "web", endpoint: this.endpoint } : null
  }

  #send(method, payload = null) {
    const headers = { "X-CSRF-Token": this.#token() }
    const options = {
      method,
      headers,
      credentials: "same-origin",
      keepalive: true
    }

    if (payload) {
      headers["Content-Type"] = "application/json"
      options.body = JSON.stringify(payload)
    }

    return fetch(this.urlValue, options).catch(() => null)
  }

  #beat() {
    if (this.stopped || this.paused || this.left || document.hidden) return

    const payload = this.#payload()
    this.#send("POST", payload).then(response => {
      // A subscription may have expired or been removed since the page loaded.
      // Fall back to ordinary presence rather than making the room look closed.
      if (response?.status === 422 && payload && !this.stopped && !this.paused && !this.left) {
        this.endpoint = null
        this.#send("POST")
      }
    })
  }

  #leave() {
    this.#stopTimer()
    if (!this.urlValue || this.left || !this.ready) return

    this.left = true
    this.#send("DELETE", this.#payload())
  }
}
