#!/usr/bin/env node
// compare_render_canon.js — close the loop: measure the RENDER against the
// measured reference canon (13 curated Dilla tracks, demucs stems, same analyzer).
// Pure Node, no deps. Laws: TRUTHFUL_STATUS, EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY.
'use strict';
const fs = require('fs');
const CANON = process.env.DILLA_CANON_JSON || '/home/z/my-project/dilla-analysis/canon_evidence.json';
const RA = process.env.DILLA_RENDER_ANALYSIS_DIR || '/home/z/my-project/dilla-analysis/render_analysis';

const canon = JSON.parse(fs.readFileSync(CANON, 'utf8'));
const rows = canon.tracks.filter(t => t.measured && t.measured.drums && t.measured.mix);
const R = n => Math.round(n * 1000) / 1000;

function load(p) { return JSON.parse(fs.readFileSync(p, 'utf8')); }
const rd = load(`${RA}/dilla.drums.json`);
const rm = load(`${RA}/dilla.mix.json`);

// ---- helpers ----------------------------------------------------------------
const median = a => { const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const stats = a => ({ n: a.length, median: R(median(a)), min: R(Math.min(...a)), max: R(Math.max(...a)) });
// tempo fold candidates: multipliers that map one detected rate onto its metric mirrors
const MULTS = [1, 2, 0.5, 1.5, 2 / 3, 3 / 4, 4 / 3, 3];
const foldCandidates = bpm => [...new Set(MULTS.map(m => Math.round(bpm * m * 10) / 10))].filter(b => b >= 70 && b <= 140);
const inWindow = cands => cands.filter(b => b >= 85 && b <= 95); // window established in REFERENCE_ANALYSIS.md
const cos = (a, b) => { let d = 0, na = 0, nb = 0; for (let i = 0; i < a.length; i++) { d += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; } return R(d / Math.sqrt(na * nb)); };

// ---- canon aggregates -------------------------------------------------------
const c = {
  swing: rows.map(t => t.measured.drums.swing_position_pct),
  onGrid: rows.map(t => (t.measured.drums.on_grid_share ?? (t.measured.drums.grid16 && t.measured.drums.grid16.on_grid_share))).filter(v => typeof v === 'number'),
  off8: rows.map(t => t.measured.drums.off8_residual_ms),
  kick: rows.map(t => t.measured.drums.band_energy_share.kick_low),
  snare: rows.map(t => t.measured.drums.band_energy_share.snare_mid),
  hat: rows.map(t => t.measured.drums.band_energy_share.hat_high),
};
const canonDrumBpm = rows.map(t => t.measured.drums.tempo.bpm);
const canonMixBpm = rows.map(t => t.measured.mix.tempo ? t.measured.mix.tempo.bpm : null).filter(Boolean);
const playersRow = rows.find(t => t.slug === 'players');

// ---- render side ------------------------------------------------------------
const rSwing = rd.grid16.swing_position_pct, rOnGrid = rd.grid16.on_grid_share, rOff8 = rd.grid16.off8_residual_ms;
const rBands = rd.band_energy_share;
const rDrumCands = foldCandidates(rd.tempo.bpm), rDrumWin = inWindow(rDrumCands);
const rMixCands = foldCandidates(rm.tempo.bpm), rMixWin = inWindow(rMixCands);
const canonDrumCands = canonDrumBpm.map(b => ({ slug: rows[canonDrumBpm.indexOf(b)].slug, raw: b, cands: foldCandidates(b), win: inWindow(foldCandidates(b)) }));

// ---- verdict table ----------------------------------------------------------
const table = [];
function cmp(name, unit, canonArr, renderVal, okFn, note) {
  const s = stats(canonArr);
  const within = okFn(s, renderVal);
  table.push({ metric: name, unit, canon: s, render: R(renderVal), within_canon: within, note: note || '' });
}
cmp('drum swing position', '%', c.swing, rSwing, s => rSwing >= s.min && rSwing <= s.max, 'measured off-8th placement, not the declared nominal');
cmp('on-grid share (16)', 'share', c.onGrid, rOnGrid, s => rOnGrid >= s.min && rOnGrid <= s.max);
cmp('off-8th residual', 'ms', c.off8, rOff8, s => rOff8 >= s.min && rOff8 <= s.max);
cmp('kick low-band share', 'share', c.kick, rBands.kick_low, s => rBands.kick_low >= s.min && rBands.kick_low <= s.max, 'drums stem, <130Hz');
cmp('snare mid-band share', 'share', c.snare, rBands.snare_mid, s => rBands.snare_mid >= s.min && rBands.snare_mid <= s.max, 'drums stem, bp@400');
cmp('hat high-band share', 'share', c.hat, rBands.hat_high, s => rBands.hat_high >= s.min && rBands.hat_high <= s.max, 'drums stem, >5kHz');

// tempo verdict: does a fold mirror of the render land in the canon 85-95 window?
const tempoVerdict = {
  render_drums_raw_bpm: rd.tempo.bpm, render_drums_fold_candidates: rDrumCands, render_drums_in_85_95: rDrumWin,
  render_mix_raw_bpm: rm.tempo.bpm, render_mix_in_85_95: inWindow([rm.tempo.bpm]),
  canon_drums_raw: canonDrumBpm.map(b => R(b)),
  canon_rows_with_85_95_mirror: canonDrumCands.filter(x => x.win.length > 0).length,
  canon_rows_total: canonDrumCands.length,
  render_matches_declared_93: rDrumWin.some(b => Math.abs(b - 93) <= 1.5) || Math.abs(rm.tempo.bpm - 93) <= 1.5,
  note: 'autocorrelation locks differ per row (half/double/dotted mirrors); window 85-95 established in REFERENCE_ANALYSIS.md',
};

// key verdict: render mix Krumhansl vs canon mix estimates, and chroma geometry
const canonKeys = rows.map(t => ({ slug: t.slug, key: t.measured.mix.key_estimate.key, mode: t.measured.mix.key_estimate.mode, r: t.measured.mix.key_estimate.r }));
const keyVerdict = {
  render_key_estimate: rm.key_estimate,
  canon_max_r: R(Math.max(...canonKeys.map(k => k.r))),
  canon_median_r: R(median(canonKeys.map(k => k.r))),
  declared_key_family: 'Eb (Ebm progression "players")',
  render_pitch_class_matches_Eb: /D#|Eb|Ebm/.test(`${rm.key_estimate.key} ${rm.key_estimate.mode}`),
  canon_estimates: canonKeys, canon_note: 'canon estimates are weak-correlation single-method (max r see table); no canon row may be treated as authority (EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY)',
};
const chromaVerdict = {
  render_vs_players_chroma_cosine: playersRow ? cos(rm.chroma, playersRow.measured.mix.chroma) : null,
  note: playersRow ? 'same analyzer, same chroma pipeline' : 'players row missing',
};

const out = {
  assembled: new Date().toISOString(),
  render: {
    file: process.env.DILLA_RENDER_WAV || 'the rendered take (see session sidecar sha256)',
    session_progression: 'players (recovered), Ebm, 93 bpm, los_angeles groove, kit_dust, 24 bars',
    declared_swing_nominal: 54.0,
  },
  canon: { rows: rows.length, slugs: rows.map(t => t.slug), method: canon.method, limits: canon.limits },
  metrics: table,
  tempo_verdict: tempoVerdict,
  key_verdict: keyVerdict,
  chroma_verdict: chromaVerdict,
  honest_gaps: [
    'levels are NOT compared: SoundCloud transcodes decode >0 dBFS on canon rows; levels are relative evidence only (canon limits)',
    'centroid_hz unit is broken in the shared analyzer (values ~1e8); comparable across both sides only as a relative rank, so omitted',
    'canon rows are 30s official previews or fan uploads, mono-transcoded; render is a 64.5s stereo mix - window difference kept',
    'sample_flip=null: the render uses no actual Dilla sample material (sample_rights_status not_used); identity is measured-groove-and-harmony, not audio identity',
  ],
};
fs.writeFileSync(`${RA}/RENDER_VS_CANON.json`, JSON.stringify(out, null, 1));

// ---- stdout summary ---------------------------------------------------------
console.log('RENDER vs CANON (13 measured curated tracks, same analyzer, same demucs)');
for (const t of table) {
  console.log(`${t.within_canon ? 'PASS' : 'MISS'}  ${t.metric}  render=${t.render}${t.unit === '%' ? '%' : ''}  canon med=${t.canon.median} [${t.canon.min}..${t.canon.max}] n=${t.canon.n}`);
}
console.log(`tempo: drums raw ${rd.tempo.bpm} -> mirrors in 85-95: ${rDrumWin.join(', ') || 'none'}; mix raw ${rm.tempo.bpm} (direct hit=${tempoVerdict.render_matches_declared_93})`);
console.log(`canon rows with an 85-95 mirror: ${tempoVerdict.canon_rows_with_85_95_mirror}/${tempoVerdict.canon_rows_total}`);
console.log(`key: render ${rm.key_estimate.key} ${rm.key_estimate.mode} r=${rm.key_estimate.r} (Eb-family match=${keyVerdict.render_pitch_class_matches_Eb}; canon r median=${keyVerdict.canon_median_r}, max=${keyVerdict.canon_max_r})`);
console.log(`chroma cosine vs players reference mix: ${chromaVerdict.render_vs_players_chroma_cosine}`);
console.log('wrote ' + `${RA}/RENDER_VS_CANON.json`);
