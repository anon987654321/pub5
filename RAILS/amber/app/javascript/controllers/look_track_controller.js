import { Controller } from "@hotwired/stimulus"

// A home look's track steps one slide at a time: the arrow keys while the
// track has focus, and the previous/next buttons beside it. The browser's own
// arrow-key scroll moved a few pixels and left the snap to settle somewhere
// near; a step lands on the next slide's start. Each button is disabled at
// its end of the track, so a press always moves something.
export default class extends Controller {
  static targets = ["track", "previous", "next", "steps"]

  connect() {
    if (this.hasStepsTarget) this.stepsTarget.hidden = false
    this.sync = () => this.update()
    this.trackTarget.addEventListener("scroll", this.sync, { passive: true })
    this.resize = new ResizeObserver(this.sync)
    this.resize.observe(this.trackTarget)
    this.update()
  }

  disconnect() {
    this.trackTarget.removeEventListener("scroll", this.sync)
    this.resize?.disconnect()
  }

  previous() { this.step(-1) }
  next() { this.step(1) }

  step(direction) {
    const carousel = this.application.getControllerForElementAndIdentifier(this.trackTarget, "carousel")
    if (!carousel?.swiper) return
    direction > 0 ? carousel.swiper.slideNext() : carousel.swiper.slidePrev()
  }

  update() {
    const track = this.trackTarget
    const end = track.scrollWidth - track.clientWidth
    if (this.hasPreviousTarget) this.previousTarget.disabled = track.scrollLeft <= 1
    if (this.hasNextTarget) this.nextTarget.disabled = track.scrollLeft >= end - 1
  }
}
