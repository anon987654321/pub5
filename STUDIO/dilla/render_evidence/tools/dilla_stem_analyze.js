#!/usr/bin/env node
// dilla_stem_analyze.js — measured per-stem evidence for the curated Dilla canon.
// Input on stdin: raw f32le mono PCM at 22050 Hz (pipe from ffmpeg).
// Output on stdout: one JSON object.
// Governing laws: TRUTHFUL_STATUS (measured state, evidence of its class),
// EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY (bounded by source/method/window).
'use strict';
const fs = require('fs');

const SR = 22050;

// ---- read stdin ------------------------------------------------------------
let total = 0;
{
  let data;
  try { data = fs.readFileSync(0); } catch (e) { process.exit(2); }
  total = Math.floor(data.length / 4);
  var x = new Float32Array(total);
  for (let i = 0; i < total; i++) x[i] = data.readFloatLE(i * 4);
}
const N = x.length;
if (N < SR) { console.log(JSON.stringify({ error: 'input shorter than 1s' })); process.exit(1); }

// ---- levels ----------------------------------------------------------------
let peak = 0, sumsq = 0;
for (let i = 0; i < N; i++) { const a = Math.abs(x[i]); if (a > peak) peak = a; sumsq += x[i] * x[i]; }
const rms = Math.sqrt(sumsq / N);
const dbfs = (v) => (v <= 1e-9 ? -180 : 20 * Math.log10(v));

// ---- biquad (RBJ cookbook) -------------------------------------------------
function biquad(kind, f0, Q) {
  const w = 2 * Math.PI * f0 / SR, cw = Math.cos(w), sw = Math.sin(w);
  let b0, b1, b2, a0, a1, a2;
  if (kind === 'lp') { const al = sw / (2 * Q); b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = b0; a0 = 1 + al; a1 = -2 * cw; a2 = 1 - al; }
  else if (kind === 'hp') { const al = sw / (2 * Q); b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = b0; a0 = 1 + al; a1 = -2 * cw; a2 = 1 - al; }
  else { const al = sw / (2 * Q); b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * cw; a2 = 1 - al; } // bp
  return { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 };
}
function filter(x, c) {
  const y = new Float32Array(N);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < N; i++) {
    const v = c.b0 * x[i] + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2;
    x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
  }
  return y;
}
const kick = filter(x, biquad('lp', 130, 0.7));
const snr  = filter(x, biquad('bp', 400, 0.9));   // snare/boom-bap body band
const hat  = filter(x, biquad('hp', 5000, 0.7));

// ---- envelopes + onsets ----------------------------------------------------
const HOP = 128;                                    // env rate ~172.3 Hz
function envelope(sig) {
  const M = Math.floor(N / HOP), e = new Float32Array(M);
  let acc = 0;
  for (let i = 0, m = 0; i < N; i++) {
    acc += sig[i] * sig[i];
    if ((i + 1) % HOP === 0) { e[m++] = Math.sqrt(acc / HOP); acc = 0; }
  }
  return e;
}
function flux(env) { // positive derivative, normalized
  const M = env.length, f = new Float32Array(M);
  for (let m = 1; m < M; m++) { const d = env[m] - env[m - 1]; f[m] = d > 0 ? d : 0; }
  return f;
}
function onsets(env, minGapMs, k) {
  const f = flux(env), M = f.length, rate = SR / HOP;
  const gap = Math.max(1, Math.round(minGapMs / 1000 * rate));
  const win = Math.round(0.35 * rate);
  const out = [];
  let last = -1e9;
  // local adaptive threshold: mean + k * std over a sliding window
  for (let m = 1; m < M - 1; m++) {
    if (f[m] < f[m - 1] || f[m] < f[m + 1]) continue;
    let s = 0, s2 = 0, c = 0;
    for (let j = Math.max(0, m - win); j < Math.min(M, m + win); j++) { s += f[j]; s2 += f[j] * f[j]; c++; }
    const mu = s / c, sd = Math.sqrt(Math.max(0, s2 / c - mu * mu));
    if (f[m] > mu + k * sd && f[m] > 1e-5 && (m - last) >= gap) { out.push(m / rate); last = m; }
  }
  return out;
}
const envKick = envelope(kick), envSnr = envelope(snr), envHat = envelope(hat);
const onKick = onsets(envKick, 90, 2.2), onSnr = onsets(envSnr, 110, 2.0), onHat = onsets(envHat, 60, 1.8);

function bandEnergy(sig) { let s = 0; for (let i = 0; i < N; i++) s += sig[i] * sig[i]; return s; }
const eKick = bandEnergy(kick), eSnr = bandEnergy(snr), eHat = bandEnergy(hat), eAll = bandEnergy(x);

// ---- tempo: autocorrelation of combined onset envelope ----------------------
function tempoEstimate() {
  const M = envHat.length;
  const comb = new Float32Array(M);
  for (let m = 0; m < M; m++) comb[m] = envKick[m] + envSnr[m] + envHat[m];
  // remove local mean
  const rate = SR / HOP, minBpm = 55, maxBpm = 200;
  const minLag = Math.floor(rate * 60 / maxBpm), maxLag = Math.min(Math.ceil(rate * 60 / minBpm), M - 1);
  let best = 0, bestLag = 0, sum = 0, cnt = 0;
  const ac = [];
  for (let lag = minLag; lag <= maxLag; lag++) {
    let s = 0;
    for (let m = 0; m + lag < M; m++) s += comb[m] * comb[m + lag];
    s /= (M - lag);
    ac.push({ lag, v: s }); sum += s; cnt++;
  }
  if (!cnt) return { bpm: null, confidence: 0 };
  const mean = sum / cnt;
  for (const { lag, v } of ac) if (v > best) { best = v; bestLag = lag; }
  // parabolic refine
  const idx = bestLag - minLag;
  let lagR = bestLag;
  if (idx > 0 && idx < ac.length - 1) {
    const y0 = ac[idx - 1].v, y1 = ac[idx].v, y2 = ac[idx + 1].v;
    const den = (y0 - 2 * y1 + y2);
    if (den !== 0) lagR = bestLag + 0.5 * (y0 - y2) / den;
  }
  const bpm = 60 * rate / lagR;
  // fold into 60..180 (halve/double to musical range)
  let b = bpm; while (b < 60) b *= 2; while (b > 180) b /= 2;
  return { bpm: Math.round(b * 10) / 10, confidence: mean > 0 ? Math.round((best / mean) * 100) / 100 : 0 };
}

// ---- grid phase + 16-slot pattern ------------------------------------------
function gridPattern(bpm) {
  const rate = SR / HOP;
  const slotS = 60 / bpm / 4;                       // sixteenth duration
  const onsetsAll = [...onKick, ...onSnr, ...onHat];
  if (!onsetsAll.length) return null;
  // find phase (offset within one sixteenth) maximizing grid proximity
  let bestPhase = 0, bestScore = -1;
  const steps = 16;
  for (let s = 0; s < steps; s++) {
    const ph = slotS * s / steps;
    let score = 0;
    for (const t of onsetsAll) {
      const q = Math.round((t - ph) / slotS) * slotS + ph;
      const d = Math.abs(t - q);
      if (d < 0.045) score += 1 - d / 0.045;
    }
    if (score > bestScore) { bestScore = score; bestPhase = ph; }
  }
  const bars = Math.ceil((onsetsAll[onsetsAll.length - 1] + slotS) / (slotS * 16));
  const grid = { kick: Array(16).fill(0), snare: Array(16).fill(0), hat: Array(16).fill(0) };
  const counts = { kick: 0, snare: 0, hat: 0 };
  function add(list, name) {
    for (const t of list) {
      const tt = t - bestPhase;
      if (tt < -0.02) continue;
      const slot = Math.round(tt / slotS);
      const snap = Math.abs(tt - slot * slotS);
      if (snap > 0.045) continue;                    // not on grid -> off-grid count
      const s16 = ((slot % 16) + 16) % 16;
      grid[name][s16] += 1; counts[name]++;
    }
  }
  add(onKick, 'kick'); add(onSnr, 'snare'); add(onHat, 'hat');
  const norm = (arr) => { const mx = Math.max(...arr, 1); return arr.map(v => Math.round(v / mx * 100) / 100); };
  // swing: residual of onsets near the off-8th positions (slots 2 and 6 mod 8)
  let residSum = 0, residN = 0;
  for (const t of onsetsAll) {
    const tt = t - bestPhase;
    const beat = tt / (slotS * 4);
    const posInBeat = beat - Math.floor(beat);       // 0..1 within beat
    // off-8th ideal = 0.5 within beat; window ±0.125 beat
    const off8 = posInBeat - 0.5;
    if (Math.abs(off8) < 0.125) { residSum += off8 * (slotS * 4) * 1000; residN++; } // ms
  }
  const beatS = slotS * 4;
  return {
    phase_ms: Math.round(bestPhase * 1000),
    grid: { kick: norm(grid.kick), snare: norm(grid.snare), hat: norm(grid.hat) },
    on_grid_share: (() => { const tot = onKick.length + onSnr.length + onHat.length; const g = counts.kick + counts.snare + counts.hat; return tot ? Math.round(g / tot * 100) / 100 : 0; })(),
    off8_residual_ms: residN ? Math.round(residSum / residN * 10) / 10 : null,
    swing_position_pct: residN ? Math.round((0.5 + (residSum / residN) / 1000 / beatS) * 1000) / 10 : null,
    off8_onsets: residN,
    bars_spanned: bars
  };
}

// ---- FFT: chroma + centroid -------------------------------------------------
function fft(re, im) { // in-place iterative radix-2
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k];
        const vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
        const vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi;
        re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
      }
    }
  }
}
const FFTN = 8192;
const chroma = new Array(12).fill(0);
let centroidSum = 0, frames = 0;
const hopFrames = Math.max(FFTN, Math.floor((N - FFTN) / 180));
const hann = new Float32Array(FFTN);
for (let i = 0; i < FFTN; i++) hann[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / FFTN);
const NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
for (let off = 0; off + FFTN <= N; off += hopFrames) {
  const re = new Float32Array(FFTN), im = new Float32Array(FFTN);
  for (let i = 0; i < FFTN; i++) re[i] = x[off + i] * hann[i];
  fft(re, im);
  let wsum = 0;
  for (let k = 1; k < FFTN / 2; k++) {
    const f = k * SR / FFTN;
    const p = re[k] * re[k] + im[k] * im[k];
    wsum += f * p;
    if (f < 55 || f > 2200) continue;
    // midi note -> pitch class
    const midi = 69 + 12 * Math.log2(f / 440);
    const pc = ((Math.round(midi) % 12) + 12) % 12;
    chroma[pc] += p;
  }
  centroidSum += wsum; frames++;
}
const centroid = frames ? centroidSum / frames : 0;
const chromaMax = Math.max(...chroma, 1e-12);
const chromaN = chroma.map(v => Math.round(v / chromaMax * 1000) / 1000);

// Krumhansl-Schmuckler key estimate
const KM = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const Km = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];
function corr(a, b) {
  const ma = a.reduce((s, v) => s + v, 0) / 12, mb = b.reduce((s, v) => s + v, 0) / 12;
  let num = 0, da = 0, dbb = 0;
  for (let i = 0; i < 12; i++) { const u = a[i] - ma, v = b[i] - mb; num += u * v; da += u * u; dbb += v * v; }
  return num / Math.sqrt(da * dbb || 1);
}
let bestKey = null, bestR = -2;
for (let r = 0; r < 12; r++) {
  const rot = chromaN.slice(r).concat(chromaN.slice(0, r));
  const rM = corr(rot, KM), rm = corr(rot, Km);
  if (rM > bestR) { bestR = rM; bestKey = { key: NOTES[r], mode: 'major', r: Math.round(rM * 100) / 100 }; }
  if (rm > bestR) { bestR = rm; bestKey = { key: NOTES[r], mode: 'minor', r: Math.round(rm * 100) / 100 }; }
}

const tempo = tempoEstimate();
const grid = tempo.bpm ? gridPattern(tempo.bpm) : null;

const out = {
  analyzer: 'dilla_stem_analyze.js 1.0 (node, pure JS FFT/biquad)',
  window_s: Math.round(N / SR * 100) / 100,
  sample_rate: SR,
  levels: {
    rms_dbfs: Math.round(dbfs(rms) * 100) / 100,
    peak_dbfs: Math.round(dbfs(peak) * 100) / 100,
    crest_db: Math.round(dbfs(peak / (rms || 1e-9)) * 100) / 100
  },
  band_energy_share: {
    kick_low: Math.round(eKick / eAll * 1000) / 1000,
    snare_mid: Math.round(eSnr / eAll * 1000) / 1000,
    hat_high: Math.round(eHat / eAll * 1000) / 1000
  },
  onsets: { kick: onKick.length, snare: onSnr.length, hat: onHat.length },
  tempo: tempo,
  centroid_hz: Math.round(centroid),
  chroma: chromaN,
  key_estimate: bestKey,
  grid16: grid
};
process.stdout.write(JSON.stringify(out));
