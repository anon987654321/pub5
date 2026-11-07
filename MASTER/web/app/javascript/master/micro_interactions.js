// Master Web Micro-Interactions & Eye-Blink Animation Controller
export function initializeMicroInteractions() {
  const webInput = document.getElementById("web-input");
  const promptLabel = document.getElementById("prompt-label");
  const faceContainer = document.getElementById("pixel-face-container");

  if (!webInput) return;

  // 1. Tactile Prompt Feedback on Keydown
  webInput.addEventListener("keydown", (e) => {
    if (promptLabel) {
      promptLabel.classList.add("key-active");
    }
  });

  webInput.addEventListener("keyup", () => {
    if (promptLabel) {
      promptLabel.classList.remove("key-active");
    }
  });

  // 2. Trigger Command Flash Effect on Enter
  webInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && webInput.value.trim().length > 0) {
      const inputRow = document.querySelector(".ghostty-input-row");
      if (inputRow) {
        inputRow.classList.remove("terminal-line-flash");
        // Force DOM reflow to restart animation
        void inputRow.offsetWidth;
        inputRow.classList.add("terminal-line-flash");
      }
    }
  });

  // 3. Autonomous Idle Eye Blink for Pixel Face
  if (faceContainer) {
    faceContainer.classList.add("active");
    scheduleRandomBlink(faceContainer);
  }
}

function scheduleRandomBlink(container) {
  const nextBlinkDelay = 3000 + Math.random() * 5000;

  setTimeout(() => {
    triggerEyeBlink();
    scheduleRandomBlink(container);
  }, nextBlinkDelay);
}

function triggerEyeBlink() {
  // Briefly toggle eye pixel rows to simulate natural terminal face blinking
  const eyePixels = document.querySelectorAll(".pixel-row:nth-child(10) .pixel.lit, .pixel-row:nth-child(11) .pixel.lit");

  eyePixels.forEach(p => p.style.opacity = "0.1");
  setTimeout(() => {
    eyePixels.forEach(p => p.style.opacity = "1.0");
  }, 120);
}

document.addEventListener("DOMContentLoaded", () => {
  initializeMicroInteractions();
});
