// Web Audio API Analog Mechanical Click Synthesizer with spatial panning
let audioCtx = null;

function initAudioContext() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
}

export function playSpatialKeySound(keyType, terminalElement) {
  initAudioContext();
  if (!audioCtx) return;

  const now = audioCtx.currentTime;

  // Calculate stereo pan (-1.0 left to +1.0 right) based on DOM element position
  let panValue = 0;
  if (terminalElement) {
    const rect = terminalElement.getBoundingClientRect();
    const elementCenter = rect.left + rect.width / 2;
    const viewportWidth = window.innerWidth;
    // Map center coordinate to [-1, 1] audio pan range
    panValue = Math.max(-1, Math.min(1, (elementCenter / viewportWidth) * 2 - 1));
  }

  // Create stereo panner node (falls back safely if unsupported)
  let panner = null;
  if (audioCtx.createStereoPanner) {
    panner = audioCtx.createStereoPanner();
    panner.pan.setValueAtTime(panValue, now);
  }

  // Generate sound based on key type
  if (keyType === "Spacebar") {
    playSineThud(now, panner);
  } else if (keyType === "Enter") {
    playNoiseBurst(now, 0.025, 1200, 0.2, panner);
    setTimeout(() => playNoiseBurst(audioCtx.currentTime, 0.015, 600, 0.15, panner), 15);
  } else {
    playNoiseBurst(now, 0.012, 900 + Math.random() * 300, 0.1, panner);
  }
}

function playSineThud(startTime, panner) {
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();

  osc.type = 'sine';
  osc.frequency.setValueAtTime(120, startTime);
  osc.frequency.exponentialRampToValueAtTime(40, startTime + 0.04);

  gain.gain.setValueAtTime(0.25, startTime);
  gain.gain.exponentialRampToValueAtTime(0.001, startTime + 0.04);

  osc.connect(gain);
  if (panner) {
    gain.connect(panner);
    panner.connect(audioCtx.destination);
  } else {
    gain.connect(audioCtx.destination);
  }

  osc.start(startTime);
  osc.stop(startTime + 0.04);
}

function playNoiseBurst(startTime, duration, cutoffFreq, volume, panner) {
  const bufferSize = audioCtx.sampleRate * duration;
  const buffer = audioCtx.createBuffer(1, bufferSize, audioCtx.sampleRate);
  const data = buffer.getChannelData(0);

  for (let i = 0; i < bufferSize; i++) {
    data[i] = Math.random() * 2 - 1;
  }

  const noise = audioCtx.createBufferSource();
  noise.buffer = buffer;

  const filter = audioCtx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(cutoffFreq, startTime);

  const gain = audioCtx.createGain();
  gain.gain.setValueAtTime(volume, startTime);
  gain.gain.exponentialRampToValueAtTime(0.001, startTime + duration);

  noise.connect(filter);
  filter.connect(gain);
  if (panner) {
    gain.connect(panner);
    panner.connect(audioCtx.destination);
  } else {
    gain.connect(audioCtx.destination);
  }

  noise.start(startTime);
  noise.stop(startTime + duration);
}

// Bind with terminal element reference
document.addEventListener("DOMContentLoaded", () => {
  const webInput = document.getElementById("web-input");
  const terminalContainer = document.getElementById("terminal-screen") || webInput;

  if (webInput) {
    webInput.addEventListener("keydown", (e) => {
      if (e.code === "Space") {
        playSpatialKeySound("Spacebar", terminalContainer);
      } else if (e.code === "Enter") {
        playSpatialKeySound("Enter", terminalContainer);
      } else if (e.key.length === 1 || e.key === "Backspace") {
        playSpatialKeySound("Standard", terminalContainer);
      }
    });
  }
});
