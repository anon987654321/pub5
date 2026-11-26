import { Controller } from "@hotwired/stimulus"

// Moves the primary navigation run for a mouse, which had no way to move it:
// touch swipes it natively (pan-x and scroll-snap in _brgen_navigation.scss),
// a keyboard scrolls the focused link into view, and a mouse wheel only ever
// scrolled the page underneath.
//
//   wheel   a vertical wheel scrolls the run sideways while it can still move
//           that way; at either end the event is left alone and the page scrolls
//   drag    press and pull; a move under DRAG_THRESHOLD is still a click, so a
//           link opens, and a real drag swallows the click it would end in.
//           Let go mid-pull and the run carries on and settles (momentum)
//   glide   resting the pointer in the band at either faded edge slides the run
//           toward that side, faster the deeper into the band, stopping at the end;
//           the speed eases in and out rather than jumping, so the strip follows
//           the pointer instead of lurching
//
// Reduced motion keeps wheel and drag, and drops momentum and glide: the run
// moves exactly as far as the hand does and no further.
//
// It also marks the ends (data-at-start, data-at-end) so the stylesheet can drop
// the fade on a side that has nothing more to show.
//
// Native overflow scrolling, not Swiper: touch keeps the platform's own
// momentum and scroll-snap, the strip still scrolls with JS off, and the CSS
// fade reads scrollLeft-driven end markers rather than a transform.
const DRAG_THRESHOLD = 6
const GLIDE_SPEED = 12
const GLIDE_EASE = 0.15
const FRICTION = 0.92
const REST_SPEED = 0.3
const MAX_FLING = 40

export default class extends Controller {
  static values = { edgeBand: { type: Number, default: 72 } }

  connect() {
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.glideSpeed = 0
    this.glideTarget = 0
    this.velocity = 0
    this.frame = null
    this.drag = null
    this.swallowClick = false
    this.step = this.step.bind(this)

    this.listeners = [
      ["wheel", (event) => this.wheel(event), { passive: false }],
      ["scroll", () => this.markEnds(), { passive: true }],
      ["pointerdown", (event) => this.pointerDown(event)],
      ["pointermove", (event) => this.pointerMove(event)],
      ["pointerup", (event) => this.pointerUp(event)],
      ["pointercancel", (event) => this.pointerUp(event)],
      // Ease the edge glide out; a fling already in flight keeps settling.
      ["pointerleave", () => { this.glideTarget = 0 }],
      ["click", (event) => this.click(event), { capture: true }],
      ["dragstart", (event) => event.preventDefault()],
      ["focusin", (event) => this.reveal(event.target)]
    ]
    this.listeners.forEach(([type, handler, options]) => this.element.addEventListener(type, handler, options))

    this.resizeObserver = new ResizeObserver(() => this.markEnds())
    this.resizeObserver.observe(this.element)
    this.markEnds()
  }

  disconnect() {
    this.listeners.forEach(([type, handler, options]) => this.element.removeEventListener(type, handler, options))
    this.resizeObserver.disconnect()
    this.stopGlide()
  }

  get room() {
    return this.element.scrollWidth - this.element.clientWidth
  }

  markEnds() {
    const left = this.element.scrollLeft
    this.element.toggleAttribute("data-at-start", left <= 1)
    this.element.toggleAttribute("data-at-end", left >= this.room - 1)
  }

  canMove(delta) {
    const left = this.element.scrollLeft
    return delta < 0 ? left > 0 : left < this.room - 1
  }

  wheel(event) {
    if (this.room <= 1 || event.ctrlKey) return

    const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY
    if (delta === 0 || !this.canMove(delta)) return

    event.preventDefault()
    this.stopGlide()
    this.element.scrollBy({ left: delta, behavior: "auto" })
  }

  pointerDown(event) {
    if (event.pointerType !== "mouse" || event.button !== 0 || this.room <= 1) return

    this.stopGlide()
    this.drag = { x: event.clientX, left: this.element.scrollLeft, moved: false, id: event.pointerId,
                  lastX: event.clientX, lastT: event.timeStamp, velocity: 0 }
  }

  pointerMove(event) {
    if (event.pointerType !== "mouse") return
    if (!this.drag) {
      this.followEdge(event)
      return
    }

    const distance = event.clientX - this.drag.x
    if (!this.drag.moved) {
      if (Math.abs(distance) < DRAG_THRESHOLD) return
      this.drag.moved = true
      this.stopGlide()
      this.element.setPointerCapture(this.drag.id)
      this.element.toggleAttribute("data-moving", true)
    }
    this.element.scrollLeft = this.drag.left - distance

    // Pixels per 16ms frame, smoothed, so the release speed is the hand's
    // recent speed rather than the last event's jitter.
    const elapsed = Math.max(1, event.timeStamp - this.drag.lastT)
    const sample = ((this.drag.lastX - event.clientX) / elapsed) * 16
    this.drag.velocity = this.drag.velocity * 0.6 + sample * 0.4
    this.drag.lastX = event.clientX
    this.drag.lastT = event.timeStamp
  }

  pointerUp(event) {
    if (!this.drag) return

    const drag = this.drag
    this.drag = null
    if (!drag.moved) return

    this.swallowClick = true
    if (this.element.hasPointerCapture(event.pointerId)) this.element.releasePointerCapture(event.pointerId)
    // A pause before letting go means the hand stopped; nothing to carry.
    const still = event.timeStamp - drag.lastT > 80
    if (this.motion.matches || still || Math.abs(drag.velocity) < REST_SPEED * 4) {
      this.element.toggleAttribute("data-moving", false)
      return
    }
    // Two pointer events a millisecond apart read as a huge speed; cap it.
    this.velocity = Math.max(-MAX_FLING, Math.min(MAX_FLING, drag.velocity))
    if (!this.frame) this.frame = requestAnimationFrame(this.step)
  }

  // A drag ends on a link; the click it produces is the drag's, not a choice.
  click(event) {
    if (!this.swallowClick) return

    this.swallowClick = false
    event.preventDefault()
    event.stopPropagation()
  }

  followEdge(event) {
    if (this.motion.matches || this.room <= 1) {
      this.stopGlide()
      return
    }

    const box = this.element.getBoundingClientRect()
    // Wider on a wide bar: from md up the wordmark and the sign-in control sit
    // over the outer part of each end, and the pointer only reaches the bar
    // inside them.
    const band = Math.min(Math.max(this.edgeBandValue, box.width * 0.15), box.width / 4)
    const fromStart = event.clientX - box.left
    const fromEnd = box.right - event.clientX
    let speed = 0
    if (fromStart < band) speed = -GLIDE_SPEED * (1 - fromStart / band)
    else if (fromEnd < band) speed = GLIDE_SPEED * (1 - fromEnd / band)

    // Leaving the band eases the run to rest rather than cutting it.
    this.glideTarget = speed !== 0 && this.canMove(speed) ? speed : 0
    if (this.glideTarget === 0 && this.glideSpeed === 0) return

    this.element.toggleAttribute("data-moving", true)
    if (!this.frame) this.frame = requestAnimationFrame(this.step)
  }

  // One frame loop for both motions: the edge glide eases toward its target
  // speed, and a released drag decays by FRICTION. Either one ends at rest or
  // at an end of the run.
  step() {
    this.frame = null
    let speed

    if (this.velocity !== 0) {
      this.velocity *= FRICTION
      speed = this.velocity
    } else {
      this.glideSpeed += (this.glideTarget - this.glideSpeed) * GLIDE_EASE
      speed = this.glideSpeed
    }
    if (Math.abs(speed) < REST_SPEED && (this.velocity !== 0 || this.glideTarget === 0)) {
      this.stopGlide()
      return
    }

    // At least a whole pixel a frame: scrollLeft rounds, and a shallower step
    // at the inner edge of the band would round to no movement at all.
    const before = this.element.scrollLeft
    this.element.scrollLeft = before + Math.sign(speed) * Math.max(1, Math.abs(speed))
    if (this.element.scrollLeft === before) {
      this.stopGlide()
      return
    }
    this.frame = requestAnimationFrame(this.step)
  }

  stopGlide() {
    this.glideSpeed = 0
    this.glideTarget = 0
    this.velocity = 0
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    if (!this.drag?.moved) this.element.toggleAttribute("data-moving", false)
  }

  reveal(target) {
    const link = target.closest("a")
    if (!link) return

    link.scrollIntoView({ block: "nearest", inline: "nearest", behavior: this.motion.matches ? "auto" : "smooth" })
  }
}
