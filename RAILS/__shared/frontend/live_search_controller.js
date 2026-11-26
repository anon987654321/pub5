import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input", "status"]
  // The three status lines come from the markup, in the page's language
  // (t("status.updating_results") and the rest). A form that names none
  // announces nothing rather than English on a Norwegian page.
  static values = {
    delay: { type: Number, default: 300 },
    updating: String,
    updated: String,
    failed: String
  }

  connect() {
    this.timeout = null
  }

  disconnect() {
    this.cancelPending()
  }

  cancelPending() {
    clearTimeout(this.timeout)
    this.timeout = null
  }

  input(event) {
    this.cancelPending()
    if (event?.isComposing) return
    this.timeout = setTimeout(() => this.submitForm(), this.delayValue)
  }

  filter(event) {
    // A search field emits change on blur as well as input while typing.
    // Only the other form controls need an immediate change submission.
    if (this.hasInputTarget && event.target === this.inputTarget) return
    this.submitForm()
  }

  start(event) {
    if (!this.hasFormTarget || event.target !== this.formTarget) return
    this.cancelPending()
    this.submission = event.detail?.formSubmission
    const shell = this.element.classList.contains("search") ? this.element : this.element.closest(".search")
    if (shell) {
      shell.dataset.state = "loading"
      shell.setAttribute("aria-busy", "true")
    }
    this.formTarget.setAttribute("aria-busy", "true")
    this.announce(this.updatingValue)
  }

  // A control can belong to this form from elsewhere on the page through its
  // form attribute: the storefront's filter drawer sits in the page while the
  // field it narrows sits in the header. Its change never passes through the
  // form element, so the document relays it. A control inside the form is
  // left to input() and to the form's own submit.
  relay(event) {
    const control = event.target
    if (!this.hasFormTarget || control.form !== this.formTarget || this.formTarget.contains(control)) return

    this.submitForm()
  }

  submitForm() {
    if (!this.hasFormTarget) return

    this.cancelPending()
    const action = new URL(this.formTarget.action, window.location.origin)
    action.searchParams.set("format", "turbo_stream")
    this.formTarget.action = action.pathname + action.search
    this.formTarget.requestSubmit()
  }

  announce(text) {
    if (this.hasStatusTarget && text) this.statusTarget.textContent = text
  }

  complete(event) {
    if (!this.hasFormTarget || event.target !== this.formTarget) return
    if (this.submission && event.detail?.formSubmission !== this.submission) return
    this.submission = null

    this.formTarget.removeAttribute("aria-busy")
    const succeeded = event.detail?.success !== false
    this.announce(succeeded ? this.updatedValue : this.failedValue)

    const shell = this.element.classList.contains("search") ? this.element : this.element.closest(".search")
    if (shell) {
      const q = this.hasInputTarget ? this.inputTarget.value.trim() : ""
      const resultsId = this.hasInputTarget ? this.inputTarget.getAttribute("aria-controls") : null
      const resultRegion = resultsId ? document.getElementById(resultsId) : null
      const suggestions = shell.querySelector(":scope > #search_suggestions, :scope > #search_palette_suggestions")
      const hasResults = Boolean(resultRegion?.textContent.trim())
      const hasSuggestions = Boolean(suggestions?.textContent.trim())
      const isEmpty = Boolean(q.length > 0 && succeeded && resultRegion && !hasResults && !hasSuggestions)
      const expanded = q.length > 0 && succeeded && !isEmpty
      const state = !succeeded
        ? "error"
        : q.length === 0
          ? "idle"
          : isEmpty
            ? "empty"
            : hasSuggestions && !hasResults
              ? "suggestions"
              : "results"

      shell.dataset.state = state
      shell.classList.toggle("active", expanded)
      shell.removeAttribute("aria-busy")
      if (this.hasInputTarget) this.inputTarget.setAttribute("aria-expanded", String(expanded))
    }
  }
}
