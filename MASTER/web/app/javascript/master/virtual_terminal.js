// Virtualized DOM Terminal Viewport for Master::Web
export class VirtualTerminal {
  constructor(containerEl, options = {}) {
    this.container = containerEl;
    this.lineHeight = options.lineHeight || 18; // Fixed line height in pixels
    this.overscan = options.overscan || 10;     // Extra lines rendered off-screen
    this.lines = [];

    this.initDOM();
    this.bindEvents();
  }

  initDOM() {
    this.container.style.position = "relative";
    this.container.style.overflowY = "auto";
    this.container.style.fontFamily = "'Roboto Mono', monospace";

    // Spacer element expands to full height of total log lines
    this.spacer = document.createElement("div");
    this.spacer.style.width = "100%";
    this.spacer.style.pointerEvents = "none";

    // Visible lines container absolute positioned inside viewport
    this.viewport = document.createElement("div");
    this.viewport.style.position = "absolute";
    this.viewport.style.top = "0";
    this.viewport.style.left = "0";
    this.viewport.style.right = "0";
    this.viewport.className = "terminal-output";

    this.container.appendChild(this.spacer);
    this.container.appendChild(this.viewport);
  }

  appendLine(text) {
    this.lines.push(text);
    this.updateSpacerHeight();

    // Auto-scroll to bottom if user is already near the bottom
    const isAtBottom = this.container.scrollHeight - this.container.scrollTop - this.container.clientHeight < 50;
    if (isAtBottom) {
      this.container.scrollTop = this.container.scrollHeight;
    } else {
      this.render();
    }
  }

  updateSpacerHeight() {
    this.spacer.style.height = `${this.lines.length * this.lineHeight}px`;
  }

  render() {
    const scrollTop = this.container.scrollTop;
    const viewportHeight = this.container.clientHeight;

    // Calculate visible line range
    const startIndex = Math.max(0, Math.floor(scrollTop / this.lineHeight) - this.overscan);
    const endIndex = Math.min(
      this.lines.length,
      Math.ceil((scrollTop + viewportHeight) / this.lineHeight) + this.overscan
    );

    // Position viewport slice
    this.viewport.style.transform = `translateY(${startIndex * this.lineHeight}px)`;

    // Render only visible slice
    const visibleLines = this.lines.slice(startIndex, endIndex);
    this.viewport.textContent = visibleLines.join("\n");
  }

  bindEvents() {
    this.container.addEventListener("scroll", () => {
      requestAnimationFrame(() => this.render());
    });

    window.addEventListener("resize", () => {
      requestAnimationFrame(() => this.render());
    });
  }
}
