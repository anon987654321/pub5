import { Controller } from "@hotwired/stimulus"

// The vertical feed: play whichever video is on screen, pause the rest, and
// report how much of each was actually watched.
//
// Scrolling and snapping are the browser's job (CSS scroll-snap). This decides
// what plays and what gets recorded, which is the part CSS cannot do.
export default class extends Controller {
  static targets = ["scroller", "item", "video", "soundButton"]
  static values = { signedIn: Boolean, nextUrl: String, soundOnLabel: String, soundOffLabel: String }

  connect() {
    this.muted = true
    // A reader who asked for less motion, or for less data, presses play
    // themselves: no video starts just because it scrolled into view.
    this.calm = Boolean(window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ||
      navigator.connection?.saveData)
    this.events = new Map()   // item element -> { url, watched }
    this.timers = new Map()
    this.handlers = new Map()
    this.visible = new Set()
    this.active = true

    // 0.6 rather than 1.0: a snapped item is never quite fully visible during
    // the settle, and waiting for 1.0 leaves a video paused under the reader.
    this.visibility = new IntersectionObserver(
      entries => entries.forEach(entry => this.#onVisibility(entry)),
      { threshold: [0.6] }
    )
    this.itemTargets.forEach(item => this.observeItem(item))

    // Load the next screenful before the reader reaches the end, so the feed
    // never shows a bottom.
    if (this.hasNextUrlValue && this.nextUrlValue) this.#watchForEnd()
  }

  disconnect() {
    this.active = false
    this.visibility?.disconnect()
    this.endWatcher?.disconnect()
    this.handlers.forEach((_handlers, item) => this.unobserveItem(item))
    this.#reportAll()
  }

  // Sound is opt-in: iOS refuses to autoplay anything unmuted, and a feed that
  // starts making noise on open is a feed people close.
  toggleSound(event) {
    this.muted = !this.muted
    this.videoTargets.forEach(video => { video.muted = this.muted })
    // Every item's button says the same thing, because sound is one setting
    // for the whole feed, not one per clip.
    const label = this.muted ? this.soundOnLabelValue : this.soundOffLabelValue
    this.soundButtonTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(!this.muted))
      if (label) button.textContent = label
    })
  }

  itemTargetConnected(item) {
    // Appended items (the next page) need observing too.
    if (this.active) this.observeItem(item)
  }

  itemTargetDisconnected(item) {
    this.unobserveItem(item)
  }

  observeItem(item) {
    if (this.handlers.has(item)) return
    const video = item.querySelector("video")
    if (!video) return

    const play = () => {
      if (this.visible.has(item)) this.#startTracking(item, video)
    }
    const pause = () => this.#stopTracking(item, video)
    this.handlers.set(item, { video, play, pause })
    video.muted = this.muted
    video.addEventListener("play", play)
    video.addEventListener("pause", pause)
    this.visibility.observe(item)
  }

  unobserveItem(item) {
    const handlers = this.handlers?.get(item)
    if (!handlers) return

    const { video, play, pause } = handlers
    this.visible.delete(item)
    video.removeEventListener("play", play)
    video.removeEventListener("pause", pause)
    video.pause()
    this.#stopTracking(item, video)
    this.visibility?.unobserve?.(item)
    this.handlers.delete(item)
  }

  #onVisibility(entry) {
    const item = entry.target
    const video = item.querySelector("video")
    if (!video) return

    const visible = entry.isIntersecting && (entry.intersectionRatio ?? 1) >= 0.6
    if (visible) {
      this.visible.add(item)
      video.muted = this.muted
      video.controls = true
      if (!this.calm) video.play().catch(() => {})
    } else {
      this.visible.delete(item)
      video.pause()
      this.#stopTracking(item, video)
    }
  }

  async #startTracking(item, video) {
    if (!this.active || !this.signedInValue || this.timers.has(item)) return

    // Install the timer before the network round-trip, so leaving the clip
    // during event creation cannot leave a timer running for a paused video.
    const state = this.events.get(item) || { url: null, watched: 0 }
    const firstPlay = !this.events.has(item)
    this.events.set(item, state)
    const timer = setInterval(() => {
      state.watched = Math.max(state.watched, video.currentTime ?? 0)
    }, 1000)
    this.timers.set(item, timer)

    if (firstPlay) {
      try {
        const response = await fetch(item.dataset.viewEventsUrl, {
          method: "POST",
          headers: {
            "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "",
            "Accept": "application/json"
          },
          credentials: "same-origin"
        })
        if (response.ok) {
          const body = await response.json()
          state.url = body.url
          if (!this.timers.has(item)) this.#report(item)
        }
      } catch (_) { /* a feed that cannot record still has to play */ }
    }
  }

  #stopTracking(item, video) {
    const timer = this.timers.get(item)
    if (!timer) return

    clearInterval(timer)
    this.timers.delete(item)
    const state = this.events.get(item)
    if (state) state.watched = Math.max(state.watched, video.currentTime ?? 0)
    this.#report(item)
  }

  #report(item) {
    const state = this.events.get(item)
    if (!state?.url || state.watched < 1) return

    const body = new FormData()
    body.append("watch_time_seconds", Math.round(state.watched))
    body.append("_method", "patch")
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) body.append("authenticity_token", token)
    // sendBeacon: these fire on scroll-away and on unload, and the browser
    // cancels in-flight fetches on unload.
    navigator.sendBeacon?.(state.url, body)
  }

  #reportAll() {
    this.events.forEach((_state, item) => this.#report(item))
  }

  #watchForEnd() {
    const last = this.itemTargets[this.itemTargets.length - 1]
    if (!last) return

    this.endWatcher = new IntersectionObserver(entries => {
      if (!entries.some(entry => entry.isIntersecting)) return
      this.endWatcher.disconnect()
      this.#loadMore()
    }, { threshold: [0.1] })
    this.endWatcher.observe(last)
  }

  async #loadMore() {
    try {
      const response = await fetch(this.nextUrlValue, {
        headers: { "Accept": "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (!response.ok || !this.active) return
      const html = await response.text()
      if (!this.active) return
      const before = this.itemTargets.length
      window.Turbo?.renderStreamMessage(html)
      // Turbo renders the stream on the next repaint; this frame runs after it.
      requestAnimationFrame(() => this.#afterPage(before))
    } catch (_) { /* the feed still holds what it has */ }
  }

  // The next page starts where the feed now ends. A page that added nothing
  // is the bottom: re-arming on the same, still visible, last item fetched
  // empty pages in a loop.
  #afterPage(before) {
    if (!this.active) return
    const count = this.itemTargets.length
    if (count === before) {
      this.nextUrlValue = ""
      return
    }
    this.nextUrlValue = this.#offsetUrl(this.nextUrlValue, count)
    this.#watchForEnd()
  }

  #offsetUrl(url, offset) {
    try {
      const parsed = new URL(url, window.location.origin)
      parsed.searchParams.set("offset", String(offset))
      return parsed.pathname + parsed.search
    } catch (_) {
      return ""
    }
  }
}
