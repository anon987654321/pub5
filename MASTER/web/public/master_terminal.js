// The operator web terminal: draws the face bitmap, keeps a virtualised
// scrollback and sends each line to /chat/command, MASTER's one authenticated
// CLI channel. Nothing in this file runs a command.
(() => {
  "use strict"

  // 32x64 binary matrix: the MASTER pixel face.
  const FACE_BITMAP = [
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000011111111111111111111111111111111110000000000000000",
    "0000000000011111111111111111111111111111111111111110000000000000",
    "0000000001110000000000000000000000000000000000001111000000000000",
    "0000000011000000000000000000000000000000000000000011000000000000",
    "0000000110000000000000000000000000000000000000000001100000000000",
    "0000001100000000000000000000000000000000000000000000110000000000",
    "0000001100000000000000000000000000000000000000000000110000000000",
    "0000001100001111110000000000000000000000011111100000110000000000",
    "0000001100011111111000000000000000000000111111110000110000000000",
    "0000001100011100111000000000000000000000111001110000110000000000",
    "0000001100011100111000000000000000000000111001110000110000000000",
    "0000001100011111111000000000000000000000111111110000110000000000",
    "0000001100001111110000000000000000000000011111100000110000000000",
    "0000001100000000000000000000000000000000000000000000110000000000",
    "0000001100000000000000000011110000000000000000000000110000000000",
    "0000001100000000000000000111111000000000000000000000110000000000",
    "0000001100000000000000000000000000000000000000000000110000000000",
    "0000001100000000000000000000000000000000000000000000110000000000",
    "0000001100001100000000000000000000000000000000110000110000000000",
    "0000001100000110000000000000000000000000000001100000110000000000",
    "0000001100000011100000000000000000000000001110000000110000000000",
    "0000001100000000111111111111111111111111111000000000110000000000",
    "0000000110000000000000000000000000000000000000000001100000000000",
    "0000000011000000000000000000000000000000000000000011000000000000",
    "0000000001110000000000000000000000000000000000001110000000000000",
    "0000000000011111111111111111111111111111111111111100000000000000",
    "0000000000000011111111111111111111111111111111110000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000"
  ]

  const LINE_HEIGHT = 18
  const OVERSCAN = 10
  const MAX_LINES = 5000
  const PROMPT = "master: ~ $"

  function renderFace(container) {
    const rows = FACE_BITMAP.map((bits) => {
      const row = document.createElement("div")
      row.className = "pixel-row"
      for (const bit of bits) {
        const pixel = document.createElement("span")
        pixel.className = bit === "1" ? "pixel lit" : "pixel dim"
        row.appendChild(pixel)
      }
      return row
    })
    container.replaceChildren(...rows)
  }

  // Only the visible slice of the scrollback is in the DOM; a spacer holds the
  // full height so the scrollbar stays honest.
  class VirtualTerminal {
    constructor(container) {
      this.container = container
      this.lines = []
      this.spacer = document.createElement("div")
      this.spacer.className = "terminal-spacer"
      this.viewport = document.createElement("div")
      this.viewport.className = "terminal-output"
      container.replaceChildren(this.spacer, this.viewport)
      container.addEventListener("scroll", () => requestAnimationFrame(() => this.render()))
      window.addEventListener("resize", () => requestAnimationFrame(() => this.render()))
    }

    append(text) {
      const { scrollHeight, scrollTop, clientHeight } = this.container
      const atBottom = scrollHeight - scrollTop - clientHeight < LINE_HEIGHT * 3
      this.lines.push(...String(text).split("\n"))
      if (this.lines.length > MAX_LINES) this.lines.splice(0, this.lines.length - MAX_LINES)
      this.spacer.style.height = `${this.lines.length * LINE_HEIGHT}px`
      if (atBottom) this.container.scrollTop = this.container.scrollHeight
      this.render()
    }

    render() {
      const top = this.container.scrollTop
      const start = Math.max(0, Math.floor(top / LINE_HEIGHT) - OVERSCAN)
      const end = Math.min(this.lines.length, Math.ceil((top + this.container.clientHeight) / LINE_HEIGHT) + OVERSCAN)
      this.viewport.style.transform = `translateY(${start * LINE_HEIGHT}px)`
      this.viewport.textContent = this.lines.slice(start, end).join("\n")
    }
  }

  async function send(command) {
    const response = await fetch("/chat/command", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ command })
    })
    if (response.status === 401 || response.status === 403) return "master: not authenticated"
    if (response.status === 429) return "master: rate limited, try again in a minute"
    const data = await response.json().catch(() => ({}))
    return (data.output ?? `master: HTTP ${response.status}`).toString()
  }

  const face = document.getElementById("pixel-face-container")
  const scroll = document.getElementById("terminal-scroll-container")
  const input = document.getElementById("web-input")
  if (!scroll || !input) return

  if (face) renderFace(face)
  const terminal = new VirtualTerminal(scroll)
  const history = []
  let cursor = 0

  input.addEventListener("keydown", async (event) => {
    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      if (history.length === 0) return
      event.preventDefault()
      cursor = Math.min(history.length, Math.max(0, cursor + (event.key === "ArrowUp" ? -1 : 1)))
      input.value = history[cursor] ?? ""
      return
    }
    if (event.key !== "Enter" || input.readOnly) return
    const command = input.value.trim()
    if (command === "") return
    history.push(command)
    cursor = history.length
    input.value = ""
    input.readOnly = true
    terminal.append(`${PROMPT} ${command}`)
    try {
      terminal.append(await send(command))
    } catch (error) {
      terminal.append(`master: ${error?.message || error}`)
    } finally {
      input.readOnly = false
      input.focus()
    }
  })
})()
