const F_FACE_MINIMAL = window.MASTER_FACE || {};
const F_FACE_STATE = F_FACE_MINIMAL.State || window.State;

(function bootstrapUltraMinimal() {
  const body = document.body;
  // The face layout is the chat page; other pages that load this leave their chrome alone.
  const faceLayout = () => body.dataset.layout === 'face';

  let startY = 0;
  document.addEventListener('touchstart', e => { startY = e.touches[0].clientY; }, { passive: true });
  document.addEventListener('touchend', e => {
    if (e.changedTouches[0].clientY - startY < -90) {
      const zsh = document.getElementById('prompt-form');
      if (zsh) zsh.classList.add('revealed');
      if (window.ParticleKernel && window.mouthPool) F_FACE_STATE.pulse = 0.7;
    }
  }, { passive: true });

  document.addEventListener('touchstart', e => {
    if (innerWidth - e.touches[0].clientX < 55) body.dataset.edgeSwipe = '1';
  }, { passive: true });
  document.addEventListener('touchend', () => delete body.dataset.edgeSwipe);

  document.addEventListener('mousemove', (e) => {
    if (!faceLayout()) return;
    if (innerHeight - e.clientY < 56) body.dataset.edgeHover = '1';
    else delete body.dataset.edgeHover;
    resetControlsHide();
  }, { passive: true });

  let controlsIdleTimer = null;
  function resetControlsHide() {
    clearTimeout(controlsIdleTimer);
    body.classList.remove('controls-hidden');
    controlsIdleTimer = setTimeout(() => {
      if (!faceLayout() || body.dataset.edgeHover === '1') return;
      body.classList.add('controls-hidden');
    }, 4500);
  }
  ['pointerdown', 'keydown', 'touchstart'].forEach((ev) => document.addEventListener(ev, resetControlsHide, { passive: true }));
  resetControlsHide();

  const cvEl = document.getElementById('face');
  if (cvEl) {
    let t = null;
    cvEl.addEventListener('pointerdown', () => {
      clearTimeout(t);
      t = setTimeout(() => {
        // face.part5 defines _chatSpeakLast; there is no /voice command to
        // fall back to, and the one that was here reached the model as prose.
        window._chatSpeakLast?.();
        if (F_FACE_STATE) F_FACE_STATE.pulse = 1.1;
      }, 480);
    });
    ['pointerup', 'pointerleave', 'pointercancel', 'lostpointercapture'].forEach(ev => cvEl.addEventListener(ev, () => clearTimeout(t)));
  }

  let camera = null, cameraTimer = null, cameraVideo = null, cameraRequest = 0;
  function disableCamTracking() {
    cameraRequest += 1;
    clearInterval(cameraTimer);
    cameraTimer = null;
    camera?.getTracks().forEach(track => track.stop());
    camera = null;
    if (cameraVideo) cameraVideo.srcObject = null;
    cameraVideo = null;
  }

  async function enableCamTracking() {
    if (!faceLayout() || !F_FACE_STATE || document.hidden) return false;
    disableCamTracking();
    const request = cameraRequest;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: 240, height: 180 }
      });
      if (request !== cameraRequest || document.hidden) {
        stream.getTracks().forEach(track => track.stop());
        return false;
      }
      camera = stream;
      const v = cameraVideo = document.createElement('video');
      v.muted = true;
      v.playsInline = true;
      v.srcObject = stream;
      await v.play();
      if (request !== cameraRequest) return false;
      const c = document.createElement('canvas');
      const ctx = c.getContext('2d', { willReadFrequently: true });
      c.width = 120; c.height = 90;

      if (!ctx) throw new Error("camera canvas unavailable");
      cameraTimer = setInterval(() => {
        if (document.hidden || v.readyState < 2) return;
        ctx.drawImage(v, 0, 0, c.width, c.height);
        const d = ctx.getImageData(0, 0, c.width, c.height).data;
        let sx = 0, sy = 0, n = 0;
        for (let i = 0; i < d.length; i += 4) {
          if ((d[i] + d[i+1] + d[i+2]) / 3 > 65) {
            const p = i / 4;
            sx += p % c.width;
            sy += (p / c.width) | 0;
            n++;
          }
        }
        if (n > 40) {
          const nx = (sx / n / c.width - 0.5) * 2.1;
          const ny = (sy / n / c.height - 0.5) * 1.3;
          F_FACE_STATE.mouseX = nx;
          F_FACE_STATE.mouseY = ny;
          if (Math.abs(nx) < 0.3 && Math.abs(ny) < 0.3) {
            F_FACE_STATE.pulse = Math.max(F_FACE_STATE.pulse || 0, 0.5);
          }
        }
      }, 160);
      return true;
    } catch (err) {
      if (request === cameraRequest) disableCamTracking();
      window.MASTER_LOG?.warn?.("face_minimal_ui:cam_tracking", err);
      return false;
    }
  }
  window.addEventListener('pagehide', disableCamTracking);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) disableCamTracking();
  });
  // Only on an explicit call. FAIL_SAFE_DEFAULTS: loading the page on a phone
  // is not consent to the camera, and a permission prompt nobody asked for is
  // denied and then remembered for the origin, as face.part5 says of the mic.

  window.MASTERMinimalUI = {
    enableCam: enableCamTracking,
    disableCam: disableCamTracking,
    revealConsole: () => {
      const z = document.getElementById('prompt-form');
      if (z) z.classList.add('revealed');
    },
    triggerVoice: (text) => {
      if (window.sendMessage) window.sendMessage(`/voice ${text || 'last'}`);
    }
  };

  if ('SpeechRecognition' in window || 'webkitSpeechRecognition' in window) {
    const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
    const rec = new SpeechRec();
    rec.continuous = false;
    rec.lang = 'en-US';
    rec.onresult = (ev) => {
      const t = ev.results[0][0].transcript.toLowerCase();
      if (/\b(voice|speak|say)\b/.test(t)) {
        const cmd = t.replace(/\b(voice|speak|say|hey|ok)\b/gi, '').trim();
        if (cmd && window.sendMessage) window.sendMessage(`/voice ${cmd}`);
      }
    };
    // rec.start() throws InvalidStateError when recognition is already
    // running (including the main STT mic), and a bare keydown listener
    // hijacked "?" even while typing in the chat box. Guard both.
    let voiceRecActive = false;
    rec.onend = () => { voiceRecActive = false; };
    rec.onerror = () => { voiceRecActive = false; };
    const safeStart = () => {
      if (voiceRecActive) return;
      try { rec.start(); voiceRecActive = true; } catch (err) { window.MASTER_LOG?.warn?.("face_minimal_ui:voice_rec_start", err); }
    };
    // The '?' key belongs to the shortcut sheet. Voice capture must never
    // compete with help or start an unsolicited second recognition session.
    window.startVoiceRec = safeStart;
  }
})();
