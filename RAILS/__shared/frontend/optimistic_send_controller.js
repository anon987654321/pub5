import { Controller } from "@hotwired/stimulus"

// Show the message the instant it is sent, not when the server gets round to it.
//
// Measured on the ambient chat widget before this existed: between pressing
// send and anything at all changing on screen, 2746ms / 4859ms / 5340ms across
// three consecutive sends. The composer kept the text, the log did not move,
// and there was no pending state anywhere — so the correct read of the UI was
// "nothing happened". People retype or press send again.
//
// Most of that is round-trip: the message is written, then broadcast back
// through Message#broadcasts_to, and only the broadcast paints. That is the
// right architecture — one code path renders every message, wherever it came
// from — but it means the sender waits for the same trip as everyone else with
// no local echo. This adds the echo and nothing else: the server stays the
// single source of truth for what a message IS.
//
// Deliberately NOT done inside conversation_log_controller's MutationObserver.
// That observer watches the log and writing to the log from inside it is what
// produced the 100%-CPU spin in 951dcd00d. This controller owns the FORM and
// only ever touches the log from a submit event.
//
// A send that did not get through stays on screen as a failed line and is
// sent again — by a tap on it, or by itself when the connection comes back —
// rather than being lost or retyped. Every attempt carries a token (the form's
// client_token field, when it has one) that the retries share, so a send whose
// answer was lost on the way back is recognised by the server and not written
// twice. A changed payload gets a new token at submit time.
export default class extends Controller {
  static targets = ["token"]
  static values = {
    // Filled from the server so the placeholder matches the real thing.
    handle: { type: String, default: "" },
    pendingLabel: { type: String, default: "sending…" },
    failedLabel: { type: String, default: "not sent — tap to retry" },
    offlineLabel: { type: String, default: "offline — sends when you are back" }
  }

  connect() {
    this.pending = null
    this.failed = null
    this.retryOnReconnect = false
    this.attempt = null
    this.onStart = this.#start.bind(this)
    this.onEnd = this.#end.bind(this)
    this.onSubmit = this.#prepare.bind(this)
    this.onOnline = this.#reconnected.bind(this)
    this.onTap = this.#tapped.bind(this)
    this.element.addEventListener("turbo:submit-start", this.onStart)
    this.element.addEventListener("turbo:submit-end", this.onEnd)
    this.element.addEventListener("submit", this.onSubmit, true)
    window.addEventListener("online", this.onOnline)
    this.log = this.element.closest(".nearby-chat-widget-panel, .messenger-pane")
      ?.querySelector(".conversation-log")
    this.log?.addEventListener("click", this.onTap)
    this.log?.addEventListener("keydown", this.onTap)
    this.#rotateToken()
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.onStart)
    this.element.removeEventListener("turbo:submit-end", this.onEnd)
    this.element.removeEventListener("submit", this.onSubmit, true)
    window.removeEventListener("online", this.onOnline)
    this.log?.removeEventListener("click", this.onTap)
    this.log?.removeEventListener("keydown", this.onTap)
    this.#clearPending()
    this.failed?.remove()
    this.failed = null
  }

  get #field() {
    return this.element.querySelector("textarea, input[type=text]")
  }

  #payload() {
    const value = (name) => this.element.querySelector(`[name="message[${name}]"]`)?.value ?? ""
    return [this.#field?.value ?? "", value("parent_id"), value("message_type"),
      value("duration_seconds"), this.element.querySelector('input[type="file"]')?.files?.[0] ?? null]
  }

  #sameAttempt(payload) {
    return this.attempt?.every((value, i) => value === payload[i]) ?? false
  }

  // Capture before Turbo builds FormData. An unchanged payload keeps its token.
  #prepare() {
    const payload = this.#payload()
    if (this.attempt && !this.#sameAttempt(payload)) this.#rotateToken()
    this.attempt = payload
  }

  #start() {
    const field = this.#field
    const text = field?.value
    this.failed?.remove()
    this.failed = null
    this.retryOnReconnect = false
    if (!text?.trim() || !this.log) return

    this.sentText = text
    // Clear immediately: the box emptying is the strongest signal that the tap
    // registered, and it is the one thing that used to take five seconds.
    field.value = ""
    field.dispatchEvent(new Event("input", { bubbles: true }))

    const log = this.log
    const li = document.createElement("li")
    li.setAttribute("role", "listitem")
    li.dataset.optimistic = "true"
    li.innerHTML = `<article data-from="self" aria-busy="true">
      <header><span class="msg-nick">${this.#escape(this.handleValue)}</span>
      <span class="send-status">· ${this.#escape(this.pendingLabelValue)}</span></header>
      <p></p></article>`
    li.querySelector("p").textContent = text
    log.appendChild(li)
    log.scrollTop = log.scrollHeight
    this.pending = li
  }

  #end(event) {
    if (!this.pending) {
      // A send with no text to echo (a photo, a voice note) still used its token.
      if (event.detail?.success === true) {
        this.attempt = null
        this.#rotateToken()
      }
      return
    }

    if (event.detail?.success === false) {
      // Keep the line, say why, and put the text back rather than lose it. No
      // fetchResponse means the request never got an answer: a dropped
      // connection, which is the case worth retrying by itself.
      const offline = !event.detail?.fetchResponse
      const article = this.pending.querySelector("article")
      article?.setAttribute("data-failed", "true")
      article?.removeAttribute("aria-busy")
      if (article) article.tabIndex = 0
      const note = this.pending.querySelector(".send-status")
      this.retryOnReconnect = offline && this.hasTokenTarget && !!this.attempt && !this.attempt[4]
      const label = this.retryOnReconnect && navigator.onLine === false ? this.offlineLabelValue : this.failedLabelValue
      if (note) note.textContent = `· ${label}`
      const field = this.#field
      if (field && !field.value) {
        field.value = this.sentText
        field.dispatchEvent(new Event("input", { bubbles: true }))
      }
      this.failed = this.pending
      this.pending = null
      return
    }

    // Success: the real message arrives through the broadcast that renders
    // every message the same way. Drop the placeholder so there is exactly one.
    this.retryOnReconnect = false
    this.attempt = null
    this.#clearPending()
    this.#rotateToken()
  }

  // A tap, or Enter/Space from the keyboard, on the failed line.
  #tapped(event) {
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return

    const line = event.target.closest?.("li[data-optimistic='true'] article[data-failed='true']")
    if (!line || line.closest('li') !== this.failed) return

    event.preventDefault()
    this.#retry()
  }

  #reconnected() {
    if (this.failed && this.retryOnReconnect) this.#retry()
  }

  #retry() {
    // Never submit a changed draft, reply target, or attachment on reconnect.
    // A deliberately cleared composer is not permission to restore and send.
    if (!this.failed || this.pending || !this.hasTokenTarget ||
        !this.#sameAttempt(this.#payload())) return
    this.element.requestSubmit?.()
  }

  #rotateToken() {
    if (!this.hasTokenTarget) return
    this.tokenTarget.value = crypto.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`
  }

  #clearPending() {
    this.pending?.remove()
    this.pending = null
  }

  #escape(value) {
    const d = document.createElement("div")
    d.textContent = value ?? ""
    return d.innerHTML
  }
}
