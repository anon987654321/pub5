// Sliding Window Log Trimmer for Web Terminal
const MAX_TERMINAL_LINES = 1000;

export function appendTerminalOutput(terminalLogElement, newText) {
  if (!terminalLogElement) return;

  // Append new text
  terminalLogElement.textContent += newText;

  // Split into lines to check capacity
  const lines = terminalLogElement.textContent.split("\n");

  if (lines.length > MAX_TERMINAL_LINES) {
    // Retain only the most recent N lines
    const trimmedLines = lines.slice(lines.length - MAX_TERMINAL_LINES);
    terminalLogElement.textContent = trimmedLines.join("\n");
  }

  // Auto-scroll to bottom of window
  window.scrollTo(0, document.body.scrollHeight);
}
