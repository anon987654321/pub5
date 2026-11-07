import consumer from "./consumer"

document.addEventListener("DOMContentLoaded", () => {
  const terminalLog = document.getElementById("terminal-log")
  const webInput = document.getElementById("web-input")
  const promptLabel = document.getElementById("prompt-label")

  if (!webInput || !terminalLog) return

  const terminalChannel = consumer.subscriptions.create("Master::Web::TerminalChannel", {
    connected() {
      console.log("master: web_client0 connected to ttyWeb0 via ActionCable")
    },

    disconnected() {
      console.log("master: web_client0 disconnected from ttyWeb0")
    },

    received(data) {
      if (data.type === "dmesg") {
        terminalLog.textContent += "\n" + data.content
      } else if (data.output !== undefined) {
        // Append executed command and output
        const commandBlock = `\n${promptLabel.textContent} ${data.command}\n${data.output}`
        terminalLog.textContent += commandBlock

        // Update prompt label if provided
        if (data.prompt) {
          promptLabel.textContent = data.prompt
        }

        // Auto-scroll terminal to bottom
        window.scrollTo(0, document.body.scrollHeight)
      }
    }
  })

  // Handle command submission on Enter key
  webInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      const command = webInput.value.trim()
      if (command.length > 0) {
        terminalChannel.send({ command: command })
        webInput.value = ""
      }
    }
  })
})
