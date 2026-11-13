import { Controller } from "@hotwired/stimulus"

// css-doodle 0.60.0, the vendored official build (importmap pin "css-doodle"),
// is the library brgen sponsors and the source of the reference the operator
// could not find: a css-doodle heart over a red bloom, dating's first screen.
// The build is an IIFE that defines the <css-doodle> custom element, so a
// dynamic import is what upgrades the element and draws the mark; it runs on
// this one screen. The heart is a shape, not a timeline, so it is static by
// itself and reduced motion needs no separate path — the gentle pulse under
// motion is CSS, scoped to the container in _brgen_dating.scss.
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
    // Draw the heart. The library only defines the element; nothing animates
    // until the CSS pulse is allowed by the media query.
    loadDoodle()
  }

  pointerDown(event) {
    this.origin = { x: event.clientX, y: event.clientY }
  }

  pointerUp(event) {
    if (!this.origin) return

    const travel = Math.hypot(event.clientX - this.origin.x, event.clientY - this.origin.y)
    this.origin = null
    if (travel >= 48) this.start()
  }

  start() {
    window.Turbo ? window.Turbo.visit(this.urlValue) : window.location.assign(this.urlValue)
  }
}
