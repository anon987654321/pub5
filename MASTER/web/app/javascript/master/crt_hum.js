// Web Audio API Ambient CRT & Mains Hum Generator
let ambientCtx = null;
let ambientGain = null;
let isHumActive = false;

export function toggleCrthum() {
  if (!ambientCtx) {
    ambientCtx = new (window.AudioContext || window.webkitAudioContext)();
  }

  if (ambientCtx.state === 'suspended') {
    ambientCtx.resume();
  }

  const now = ambientCtx.currentTime;

  if (isHumActive) {
    if (ambientGain) {
      ambientGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.1);
    }
    isHumActive = false;
    return false;
  } else {
    ambientGain = ambientCtx.createGain();
    ambientGain.gain.setValueAtTime(0.0001, now);
    ambientGain.gain.exponentialRampToValueAtTime(0.012, now + 0.8); // Ultra-subtle ambient level

    // 1. Electrical Mains Hum (60 Hz sub-bass sine)
    const mainsOsc = ambientCtx.createOscillator();
    mainsOsc.type = 'sine';
    mainsOsc.frequency.setValueAtTime(60, now);

    // 2. CRT Flyback Transformer Whine (~15.75 kHz classic CRT frequency)
    const flybackOsc = ambientCtx.createOscillator();
    flybackOsc.type = 'triangle';
    flybackOsc.frequency.setValueAtTime(15750, now);

    // Bandpass filter to warm and isolate the textures
    const filter = ambientCtx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(4000, now);
    filter.Q.setValueAtTime(0.3, now);

    // Connect audio graph
    mainsOsc.connect(ambientGain);
    flybackOsc.connect(ambientGain);
    ambientGain.connect(filter);
    filter.connect(ambientCtx.destination);

    mainsOsc.start(now);
    flybackOsc.start(now);

    isHumActive = true;
    return true;
  }
}

// Bind toggle to a console key combination (e.g., Ctrl+H or UI button)
document.addEventListener("keydown", (e) => {
  if (e.ctrlKey && e.key.toLowerCase() === 'h') {
    e.preventDefault();
    const active = toggleCrthum();
    console.log(`master: ambient CRT hum status -> ${active ? "ACTIVE" : "MUTED"}`);
  }
});
