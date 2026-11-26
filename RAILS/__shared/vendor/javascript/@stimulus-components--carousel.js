import { Controller } from "@hotwired/stimulus"

// Local Stimulus carousel compatibility implementation. Native scroll snap
// owns touch momentum and layout; navigation never commits a domain action.
export default class extends Controller {
  static values = { options: Object }

  connect() {
    this.options = { ...this.defaultOptions, ...this.optionsValue }
    this.axis = this.options.direction === "vertical" ? "y" : "x"
    this.styles = new Map()
    this.setStyle(this.element, this.axis === "y" ? "overflow-y" : "overflow-x", "auto")
    this.setStyle(this.element, "scroll-snap-type", this.options.scrollSnapType || `${this.axis} mandatory`)
    this.setStyle(this.element, "scroll-behavior", this.behavior())
    if (this.options.spaceBetween != null) this.setStyle(this.element, "gap", `${this.options.spaceBetween}px`)
    this.swiper = {
      el: this.element,
      slides: [],
      slideNext: () => this.step(1),
      slidePrev: () => this.step(-1),
      update: () => this.refresh(),
      destroy: () => this.disconnect(),
    }
    this.refresh()
    this.observer = new MutationObserver(() => this.refresh())
    this.observer.observe(this.element, { childList: true })
    this.onKey = event => this.key(event)
    if (this.options.keyboard !== false) this.element.addEventListener("keydown", this.onKey)
  }

  behavior() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ? "auto" : this.options.scrollBehavior || "smooth"
  }

  setStyle(node, property, value) {
    if (!this.styles.has(node)) this.styles.set(node, new Map())
    const saved = this.styles.get(node)
    if (!saved.has(property)) saved.set(property, [node.style.getPropertyValue(property), node.style.getPropertyPriority(property)])
    node.style.setProperty(property, value)
  }

  restore(node) {
    this.styles.get(node)?.forEach(([value, priority], property) => {
      if (value) node.style.setProperty(property, value, priority)
      else node.style.removeProperty(property)
    })
    this.styles.delete(node)
  }

  refresh() {
    if (!this.swiper) return
    const slides = Array.from(this.element.children)
    for (const node of this.styles.keys()) {
      if (node !== this.element && !slides.includes(node)) this.restore(node)
    }
    slides.forEach(slide => {
      this.setStyle(slide, "scroll-snap-align", this.options.scrollSnapAlign || "start")
      if (!this.options.preserveSizing) this.setStyle(slide, "flex", this.options.slidesPerView === "auto" ? "0 0 auto" : "0 0 100%")
    })
    this.swiper.slides = slides
  }

  position(slide) {
    const rect = this.element.getBoundingClientRect()
    const item = slide.getBoundingClientRect()
    return this.axis === "y"
      ? this.element.scrollTop + item.top - rect.top - this.element.clientTop
      : this.element.scrollLeft + item.left - rect.left - this.element.clientLeft
  }

  step(direction) {
    const slides = this.swiper?.slides || []
    if (!slides.length) return
    const top = this.axis === "y"
    const offset = top ? this.element.scrollTop : this.element.scrollLeft
    const positions = slides.map(slide => this.position(slide))
    const nearest = positions.reduce((best, value, i) => Math.abs(value - offset) < Math.abs(positions[best] - offset) ? i : best, 0)
    const target = positions[Math.max(0, Math.min(slides.length - 1, nearest + direction))]
    this.element.scrollTo({ [top ? "top" : "left"]: target, behavior: this.behavior() })
  }

  key(event) {
    if (event.defaultPrevented || event.target !== this.element || event.altKey || event.ctrlKey || event.metaKey) return
    const direction = (this.axis === "y" ? { ArrowUp: -1, ArrowDown: 1 } : { ArrowLeft: -1, ArrowRight: 1 })[event.key]
    if (!direction) return
    event.preventDefault()
    this.step(direction)
  }

  disconnect() {
    this.observer?.disconnect()
    if (this.onKey) this.element.removeEventListener("keydown", this.onKey)
    if (this.styles) for (const node of this.styles.keys()) this.restore(node)
    this.swiper = null
  }

  get defaultOptions() { return {} }
}
