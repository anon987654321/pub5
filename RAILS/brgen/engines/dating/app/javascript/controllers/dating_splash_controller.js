import { Controller } from "@hotwired/stimulus"

// Upgrade the light-trail heart only on the splash. Its single 4.6-second
// pass respects reduced motion, with a static CSS mask before upgrade.
let doodlePromise = null

function loadDoodle() {
  if (doodlePromise) return doodlePromise
  doodlePromise = import("css-doodle").catch(() => null)
  return doodlePromise
}

// Dating's first screen: "sveip for å begynne". A swipe in any direction, or the
// link itself, opens the deck; without script the link alone does.
export default class extends Controller {
  static values = { url: String }
  static targets = ["heart"]

  connect() {
    loadDoodle()
  }

  pointerDown(event) {
    if (event.isPrimary === false || (event.pointerType === "mouse" && event.button !== 0)) return
    this.origin = { x: event.clientX, y: event.clientY, id: event.pointerId }
  }

  pointerUp(event) {
    if (!this.origin || this.origin.id !== event.pointerId) return

    const travel = Math.hypot(event.clientX - this.origin.x, event.clientY - this.origin.y)
    this.origin = null
    if (travel >= 48) this.start()
  }

  pointerCancel() {
    this.origin = null
  }

  start() {
    window.Turbo ? window.Turbo.visit(this.urlValue) : window.location.assign(this.urlValue)
  }
}
