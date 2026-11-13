import { Controller } from "@hotwired/stimulus"

// Dating's first screen: "sveip for å begynne". A swipe in any direction, or the
// link itself, opens the deck; without script the link alone does. Two hearts
// stand here: the operator's css-doodle heart, whose library is fetched on this
// screen only and not at all when motion is unwelcome, and the Hjerterom SVG,
// whose original SMIL motion pauses for reduced motion.
export default class extends Controller {
  static values = { url: String }
  static targets = ["hjerterom"]

  connect() {
    this.origin = null
    this.motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.motionChange = () => this.#syncMotion()
    this.motionQuery.addEventListener("change", this.motionChange)
    this.#syncMotion()

    if (this.motionQuery.matches) return

    import("css-doodle").catch(() => {})
  }

  disconnect() {
    this.motionQuery?.removeEventListener("change", this.motionChange)
  }

  #syncMotion() {
    if (!this.hasHjerteromTarget) return

    const svg = this.hjerteromTarget
    if (this.motionQuery.matches) {
      svg.setCurrentTime?.(0)
      svg.pauseAnimations?.()
    } else {
      svg.unpauseAnimations?.()
    }
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
