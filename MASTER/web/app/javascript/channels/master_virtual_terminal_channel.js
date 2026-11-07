import consumer from "./consumer"
import { VirtualTerminal } from "../master/virtual_terminal"

document.addEventListener("DOMContentLoaded", () => {
  const container = document.getElementById("terminal-scroll-container");
  if (!container) return;

  const terminal = new VirtualTerminal(container, { lineHeight: 18 });

  consumer.subscriptions.create("Master::Web::TerminalChannel", {
    received(data) {
      if (data.type === "dmesg") {
        terminal.appendLine(data.content);
      } else if (data.output !== undefined) {
        // Break multi-line execution output into individual array lines
        const formatted = `${data.prompt || "master: ~ $"} ${data.command}\n${data.output}`;
        formatted.split("\n").forEach(line => terminal.appendLine(line));
      }
    }
  });
})
