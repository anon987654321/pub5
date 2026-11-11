// plur1bus plates — the amber® mark, ten directions.
//
// One law, taken straight from the shipped mark: the ink is clipped to the
// glyph mask, and the nine swoosh hairlines ride ON TOP of the ink — clipped
// to the letter interiors as well, so nothing ever bleeds past the letter
// edges. A plate may change the ink material, the line colour and the ground;
// it may not touch the Caprasimo outlines, the hairline family, or the
// stacking order. Everything a plate adds lives inside the letters.
//
// Every plate extracts the glyph outlines and hairlines live from the logo
// partial, so font and swoosh can't drift from what ships. Seeded, reproducible.
//
// Usage: node generate.mjs   (writes plates/*.svg and all-plates.html)

import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = dirname(fileURLToPath(import.meta.url));
const OUT = join(DIR, "plates");
const ROOT = join(DIR, "../../..");
const PARTIAL = join(ROOT, "RAILS/amber/app/views/shared/_logo.html.erb");

const ERB = readFileSync(PARTIAL, "utf8");
const GLYPHS = Object.fromEntries([...ERB.matchAll(/caprasimo-([a-z]+)" d="([^"]+)"/g)].map(m => [m[1], m[2]]));
const TRANSFORMS = Object.fromEntries([...ERB.matchAll(/caprasimo-([a-z]+)" transform="([^"]+)"/g)].map(m => [m[1], m[2]]));
const HAIRLINES = [...ERB.matchAll(/<path stroke="#FFFFFF" stroke-width="([\d.]+)"[^>]*d="([^"]+)"/g)].map(m => [parseFloat(m[1]), m[2]]);

function canonicalHairlines() {
  // Preserve the source partial's nine exact white paths, widths and opacity.
  // Candidate plates clip visibility; they never restyle or redraw the swoosh.
  return HAIRLINES.map(([width, d]) =>
    `<path stroke="#FFFFFF" stroke-width="${width}" stroke-opacity="1.0" fill="none" d="${d}"/>`).join("");
}

if (Object.keys(GLYPHS).length !== 6) throw new Error("glyph extraction failed");
if (HAIRLINES.length !== 9) throw new Error("hairline extraction failed");

// ---------- geometry ----------
function mul(m, n) {
  return [
    m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
  ];
}
function parseTransform(str) {
  let m = [1, 0, 0, 1, 0, 0];
  const re = /(translate|rotate|scale)\(([^)]*)\)/g;
  let t;
  while ((t = re.exec(str))) {
    const a = t[2].trim().split(/[\s,]+/).map(Number);
    let n;
    if (t[1] === "translate") n = [1, 0, 0, 1, a[0] || 0, a[1] || 0];
    else if (t[1] === "scale") n = [a[0], 0, 0, a.length > 1 ? a[1] : a[0], 0, 0];
    else {
      const r = (a[0] || 0) * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
      n = [c, s, -s, c, 0, 0];
      if (a.length === 3) { n = mul(mul([1, 0, 0, 1, a[1], a[2]], n), [1, 0, 0, 1, -a[1], -a[2]]); }
    }
    m = mul(m, n);
  }
  return m;
}
const ap = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];

// collect all coordinate points of a path (absolute commands only in this font)
function pathPoints(d) {
  const pts = [];
  const re = /([MQCLVHZ])([^MQCLVHZ]*)/g;
  let cx = 0, cy = 0, m;
  while ((m = re.exec(d))) {
    const n = (m[2].match(/-?\d*\.?\d+(?:e-?\d+)?/g) || []).map(Number);
    let i = 0;
    if (m[1] === "M" || m[1] === "L") {
      for (; i < n.length; i += 2) { cx = n[i]; cy = n[i + 1]; pts.push([cx, cy]); }
    } else if (m[1] === "Q" || m[1] === "C") {
      for (; i < n.length; i += 2) pts.push([n[i], n[i + 1]]);
      cx = pts[pts.length - 1][0]; cy = pts[pts.length - 1][1];
    } else if (m[1] === "V") { cy = n[0]; pts.push([cx, cy]); }
    else if (m[1] === "H") { cx = n[0]; pts.push([cx, cy]); }
  }
  return pts;
}

// wordmark bounding box on the canvas
const LOCK = { x0: 1e9, y0: 1e9, x1: -1e9, y1: -1e9 };
for (const [g, d] of Object.entries(GLYPHS)) {
  const m = parseTransform(TRANSFORMS[g]);
  for (const [x, y] of pathPoints(d)) {
    const [px, py] = ap(m, x, y);
    LOCK.x0 = Math.min(LOCK.x0, px); LOCK.y0 = Math.min(LOCK.y0, py);
    LOCK.x1 = Math.max(LOCK.x1, px); LOCK.y1 = Math.max(LOCK.y1, py);
  }
}
console.log("lockup bbox:", JSON.stringify(LOCK));

// uniform tight stage centred on the lockup — the word fills the plate the
// way the frontpage sets it (nav crops to 58 105 410 108), with even margins
const W = (LOCK.x1 - LOCK.x0) + 110, H = (LOCK.y1 - LOCK.y0) + 110;
const SX = (LOCK.x0 + LOCK.x1) / 2 - W / 2;
const SY = (LOCK.y0 + LOCK.y1) / 2 - H / 2;
const VB = `${SX.toFixed(1)} ${SY.toFixed(1)} ${W} ${H}`;

// painting band: a little wider than the letters; every layer is clipped to
// the glyphs anyway, this just bounds how far textures extend before the clip
const CX0 = LOCK.x0 - 34;
const CX1 = LOCK.x1 + 58;

// sample a hairline curve (they are all one base curve translated down)
function bez(p0, p1, p2, p3, t) {
  const u = 1 - t;
  return [
    u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
    u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1],
  ];
}
function hairY(y0, x) {
  // base curve for width-row y0: M50,y0 C200,y0-80 400,y0+20 600,y0-80 S850,y0-20 950,y0-50
  const A = [[50, y0], [200, y0 - 80], [400, y0 + 20], [600, y0 - 80]];
  const r = [800, 2 * (y0 - 80) - (y0 + 20)]; // S reflects the previous control
  const B = [r, [850, y0 - 20], [950, y0 - 50]];
  for (let i = 1; i <= 80; i++) {
    const p = bez(...A, i / 80);
    if (p[0] >= x) return p[1];
    if (i === 80 && x > 600) {
      for (let j = 1; j <= 40; j++) { const q = bez(A[3], ...B, j / 40); if (q[0] >= x) return q[1]; }
      return B[2][1];
    }
  }
  return y0;
}


// frozen position of the animated radial ink (reference)
const RADIAL = [500, 250, 560];
const radT = (x, y) => Math.min(1, Math.hypot(x - RADIAL[0], y - RADIAL[1]) / RADIAL[2]);

// seeded rng
function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }

// ---------- svg helpers ----------
function defs(id) {
  const glyphs = Object.entries(GLYPHS).map(([g, d]) => `<path id="${id}-${g}" d="${d}"/>`).join("");
  const uses = Object.keys(GLYPHS).map(g => `<use href="#${id}-${g}" transform="${TRANSFORMS[g]}"/>`).join("");
  // clipPath content model takes shapes/use only — a <g> wrapper makes
  // Chromium discard the whole clip (the wordmark vanishes). Children go in bare.
  const mask = `<clipPath id="${id}-text">${uses}</clipPath>`;
  return `<defs>${glyphs}${mask}</defs>`;
}
// the ink pass: clipped to the glyph interiors
const inkG = (id, inner) => `<g clip-path="url(#${id}-text)">${inner}</g>`;
// canonical stacking, as shipped: ink clipped to the glyphs first, then the
// hairlines ride on top — clipped to the glyph interiors as well, so nothing
// bleeds past the letter edges. This is the law every plate obeys.
function mark(id, ink, linesSvg) {
  return inkG(id, ink) + `<g clip-path="url(#${id}-text)">${linesSvg}</g>`;
}
function doc(num, title, ground, body, extraDefs = "") {
  const id = `pl${num}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="${title}">` +
    `<title>${title}</title>` + defs(id) + extraDefs +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="${ground}"/>` +
    body + `</svg>`;
}
function plate(num, slug, note, svg) {
  writeFileSync(join(OUT, `${String(num).padStart(2, "0")}_${slug}.svg`), svg);
  PLATES.push({ num, slug, note });
}

// frozen brand ink (radial, as shipped)
function brandRadial(id) {
  return `<radialGradient id="${id}" gradientUnits="userSpaceOnUse" cx="500" cy="250" r="560">` +
    `<stop offset="0" stop-color="#ffb999"/><stop offset="0.33" stop-color="#e6cce6"/>` +
    `<stop offset="0.66" stop-color="#cce6cc"/><stop offset="1" stop-color="#99e6e6"/></radialGradient>`;
}

const PLATES = [];

// ---------- 01 unum stipple — many carriers, one readable form ----------
function p01() {
  const id = "pl1", r = rng(5701);
  // perforation: carriers on the left dissolve into solid ink on the right
  let holes = "";
  for (let gx = LOCK.x0 - 6; gx < LOCK.x1; gx += 4.4) {
    const u = (gx - LOCK.x0) / (LOCK.x1 - LOCK.x0);
    for (let gy = LOCK.y0 - 4; gy < LOCK.y1 + 6; gy += 4.4) {
      if (r() < 0.74 * Math.pow(Math.max(0, 1 - u * 1.55), 1.2)) {
        holes += `<circle cx="${(gx + r() * 3).toFixed(1)}" cy="${(gy + r() * 3).toFixed(1)}" r="${(1.0 + r() * 1.4).toFixed(2)}" fill="#0B0B0B"/>`;
      }
    }
  }
  let sig = "";
  for (let i = 0; i < 6; i++) sig += `<circle cx="${(LOCK.x0 + 18 + r() * 46).toFixed(1)}" cy="${(LOCK.y0 + 40 + r() * 90).toFixed(1)}" r="1.6" fill="#C8F55F"/>`;
  // The original nine white swoosh paths ride above the ink unchanged.
  const lines = canonicalHairlines();
  const ink = `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#E8E8E6"/>` + holes + sig;
  const out = doc(1, "amber mark — many perforated carriers resolve into one readable form",
    "#0B0B0B", mark(id, ink, lines));
  plate(1, "unum_stipple", "perforated ink resolving to solid; canonical white swoosh inside the glyphs", out);
}

// ---------- 02 bit8 pixel — bit-reduction ----------
function p02() {
  const id = "pl2", grid = 7, r = rng(5702);
  const pal = ["#FFE9C7", "#F2C7E2", "#CBE6C9", "#A8DDEA", "#8E7BB8"];
  let cells = "";
  for (let x = CX0; x < CX1; x += grid) {
    for (let y = LOCK.y0 - 8; y < LOCK.y1 + 8; y += grid) {
      const t = radT(x + grid / 2, y + grid / 2);
      let idx = Math.min(4, Math.round(t * 5));
      if (r() < 0.06) idx = Math.min(4, idx + 1);
      cells += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${grid}" height="${grid}" fill="${pal[idx]}"/>`;
    }
  }
  let sig = "";
  for (let i = 0; i < 4; i++) sig += `<rect x="${(LOCK.x0 + 10 + r() * 60).toFixed(0)}" y="${(LOCK.y0 + 30 + r() * 80).toFixed(0)}" width="${grid}" height="${grid}" fill="#C8F55F"/>`;
  // CRT scanlines fall on the phosphor — the ink — not on the ground
  const scan = [];
  for (let y = SY; y < SY + H; y += 6) scan.push(`<rect x="${SX}" y="${y}" width="${W}" height="1.4" fill="#000" opacity="0.12"/>`);
  const lines = canonicalHairlines();
  const out = doc(2, "amber mark — 8-bit bit-reduction with the original white swoosh",
    "#101013", mark(id, cells + sig + scan.join(""), lines));
  plate(2, "bit8_pixel", "8-bit bit-reduction — quantized ink and scanlines; canonical white swoosh", out);
}

// ---------- 03 dither4 press — 4-bit ordered dither, legible ----------
function p03() {
  const id = "pl3", cell = 6.5;
  const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map(row => row.map(v => (v + 0.5) / 16));
  let cells = "";
  for (let x = CX0; x < CX1; x += cell) {
    for (let y = LOCK.y0 - 8; y < LOCK.y1 + 8; y += cell) {
      const cxg = Math.floor(((x - CX0) / cell) % 4 + 4) % 4, cyg = Math.floor(((y - LOCK.y0) / cell) % 4 + 4) % 4;
      const b = bayer[cyg][cxg];
      // coverage ramp: ~12% dots at the left edge of the 'a', solid at the r
      const u = Math.min(1, Math.max(0, (x - LOCK.x0) / (LOCK.x1 - LOCK.x0) * 1.3));
      if (b < 0.12 + u * 0.92) cells += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${cell}" height="${cell}" fill="#17130E"/>`;
    }
  }
  const lines = canonicalHairlines();
  const out = doc(3, "amber mark — 4-bit ordered dither on paper",
    "#F2EFE6", mark(id, cells, lines));
  plate(3, "dither4_press", "4-bit ordered dither — a halftone ramp inside the glyphs; canonical white swoosh", out);
}

// ---------- 04 signal orbit — motion: the ink roams ----------
function p04() {
  const id = "pl4";
  const g = `<radialGradient id="ink4" gradientUnits="userSpaceOnUse" cx="500" cy="250" r="560">` +
    `<animate attributeName="fx" values="500;330;640;500" dur="18s" repeatCount="indefinite"/>` +
    `<animate attributeName="fy" values="250;200;300;250" dur="18s" repeatCount="indefinite"/>` +
    `<stop offset="0" stop-color="#ffb999"/><stop offset="0.33" stop-color="#e6cce6"/>` +
    `<stop offset="0.66" stop-color="#cce6cc"/><stop offset="1" stop-color="#99e6e6"/></radialGradient>`;
  const lines = canonicalHairlines();
  const ink = `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink4)"/>`;
  const out = doc(4, "amber mark — the radial ink roams behind the letters",
    "#0B0B0B", mark(id, ink, lines), g);
  plate(4, "signal_orbit", "motion — the radial ink roams inside the letters; the hairlines hold still", out);
}

// ---------- 05 hue flow — motion: the ink cycles ----------
function p05() {
  const id = "pl5";
  const stops = ["#ffb999", "#e6cce6", "#cce6cc", "#99e6e6"];
  const anim = (c, i) => `<stop offset="${i / 3}" stop-color="${c}">` +
    `<animate attributeName="stop-color" values="${stops.join(";")};${stops[0]}" dur="10s" begin="${-i * 2.5}s" repeatCount="indefinite"/></stop>`;
  const g = `<linearGradient id="ink5" gradientUnits="userSpaceOnUse" x1="${CX0}" y1="0" x2="${CX1}" y2="0">` +
    stops.map((c, i) => anim(c, i)).join("") + `</linearGradient>`;
  const lines = canonicalHairlines();
  const ink = `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink5)"/>`;
  const out = doc(5, "amber mark — the brand gradient cycles through the letters",
    "#101013", mark(id, ink, lines), g);
  plate(5, "hue_flow", "motion — palette cycling: the shipped ramp turns over inside the letters", out);
}

// ---------- 06 zoetrope frames — motion depicted, not played ----------
// The ink holds three exposure frames split inside the letters — ghost, ghost,
// live — separated by slivers of ground, the way a sprite sheet lays a strip.
function p06() {
  const id = "pl6";
  const t1 = LOCK.x0 + (LOCK.x1 - LOCK.x0) / 3, t2 = LOCK.x0 + 2 * (LOCK.x1 - LOCK.x0) / 3;
  const sliver = (x0, x1, o) =>
    `<rect x="${x0.toFixed(1)}" y="${SY}" width="${(x1 - x0).toFixed(1)}" height="${H}" fill="#E8833A" opacity="${o}"/>`;
  const ink =
    sliver(SX, t1, 0.22) + sliver(t1, t2, 0.55) + sliver(t2, SX + W, 1) +
    `<rect x="${(t1 - 1.5).toFixed(1)}" y="${SY}" width="3" height="${H}" fill="#F6F1E3"/>` +
    `<rect x="${(t2 - 1.5).toFixed(1)}" y="${SY}" width="3" height="${H}" fill="#F6F1E3"/>`;
  const lines = canonicalHairlines();
  const out = doc(6, "amber mark — three exposure frames of the ink, ghost to live, split inside the letters",
    "#F6F1E3", mark(id, ink, lines));
  plate(6, "zoetrope_frames", "sprite-sheet strip — ghost, ghost, live ink frames inside the glyphs; canonical white swoosh", out);
}

// ---------- 07 starlight — night-sky ink and stars ----------
function p07() {
  const id = "pl7", r = rng(5707);
  const g = `<linearGradient id="ink7" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
    `<stop offset="0" stop-color="#F6F8FF"/><stop offset="1" stop-color="#9FAEE0"/></linearGradient>`;
  // tiny stars scattered over the lockup; the glyph clip keeps only the ones
  // that fall inside the letters
  let stars = "";
  for (let i = 0; i < 16; i++) {
    stars += `<circle cx="${(LOCK.x0 + r() * (LOCK.x1 - LOCK.x0)).toFixed(1)}" cy="${(LOCK.y0 + r() * (LOCK.y1 - LOCK.y0)).toFixed(1)}" r="${(1.0 + r() * 0.9).toFixed(2)}" fill="#FFFFFF" opacity="${(0.6 + r() * 0.4).toFixed(2)}"/>`;
  }
  // The original white swoosh remains identical on every plate.
  const lines = canonicalHairlines();
  const ink = `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink7)"/>` + stars;
  const out = doc(7, "amber mark — night-sky ink and stars; original white swoosh unchanged",
    "#0B1020", mark(id, ink, lines), g);
  plate(7, "starlight", "night-sky ink and stars inside the glyphs; canonical white swoosh", out);
}

// ---------- 08 prism rainbow — candy ink inside the glyphs ----------
function p08() {
  const id = "pl8";
  const g = `<linearGradient id="ink8" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
    `<stop offset="0" stop-color="#F0559C"/><stop offset="0.55" stop-color="#8A4BFF"/><stop offset="1" stop-color="#0FA88A"/></linearGradient>`;
  const lines = canonicalHairlines();
  const ink = `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink8)"/>`;
  const out = doc(8, "amber mark — the candy rainbow poured into the letters",
    "#FFF6E8", mark(id, ink, lines), g);
  plate(8, "prism_rainbow", "prism ink — the rainbow lives in the letters; canonical white swoosh", out);
}

// ---------- 09 grade teal/amber — explicit cinematic grade ----------
function p09() {
  const id = "pl9";
  const g = `<linearGradient id="ink9" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
    `<stop offset="0" stop-color="#FBD1A2"/><stop offset="1" stop-color="#E89A56"/></linearGradient>`;
  const lines = canonicalHairlines();
  const ink = `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink9)"/>`;
  const out = doc(9, "amber mark — teal shadows, amber highlights; the grade is explicit",
    "#0E2B33", mark(id, ink, lines), g);
  plate(9, "grade_teal_amber", "explicit grade — teal ground, amber ink, canonical white swoosh", out);
}

// ---------- 10 duotone riso — two ink passes a hair out of register ----------
// Both passes are clipped to the glyph interiors; the navy pass is itself
// clipped twice (outer clip fixed, inner clip shifted), so the orange only
// rims the right and bottom edges — misregistration held inside the letters.
function p10() {
  const id = "pl10";
  const orange = inkG(id, `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#FF5A3C"/>`);
  const navy = `<g clip-path="url(#${id}-text)"><g transform="translate(-3 -2)" clip-path="url(#${id}-text)">` +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#1D2A5C" opacity="0.86"/></g></g>`;
  const sig = inkG(id,
    `<circle cx="${LOCK.x0 + 34}" cy="${LOCK.y0 + 52}" r="2.2" fill="#C8F55F"/>` +
    `<circle cx="${LOCK.x0 + 52}" cy="${LOCK.y0 + 96}" r="1.7" fill="#C8F55F"/>` +
    `<circle cx="${LOCK.x0 + 30}" cy="${LOCK.y0 + 120}" r="1.5" fill="#C8F55F"/>`);
  const lines = canonicalHairlines();
  const out = doc(10, "amber mark — riso duotone, two ink passes a hair out of register",
    "#F5F1E6", orange + navy + sig + `<g clip-path="url(#${id}-text)">${lines}</g>`);
  plate(10, "duotone_riso", "riso duotone — misregistration inside the glyphs; canonical white swoosh", out);
}

// ---------- reference (canonical mark, tight stage) ----------
function pref() {
  const out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 500" role="img" aria-label="canonical amber mark">` +
    `<title>canonical amber mark — production geometry and original full-width swoosh</title>` +
    defs("pl0") + brandRadial("ink0") +
    `<g clip-path="url(#pl0-text)"><rect x="0" y="100" width="1000" height="300" fill="url(#ink0)"/></g>` +
    canonicalHairlines() +
    `</svg>`;
  writeFileSync(join(OUT, "reference-original.svg"), out);
}

// ---------- avatar cuts — transparent ground, sprite-sheet sizes ----------
// The operator's workflow ships avatar-size variants with the background
// removed. Identical glyph outlines and hairline family, no ground rect —
// alpha-transparent SVGs cropped tight to the letterforms, visible only
// inside the glyphs, ready for 128 / 64 / 32 px slots.
function avatars() {
  const ADIR = join(OUT, "avatars");
  mkdirSync(ADIR, { recursive: true });
  const AX0 = LOCK.x0 - 12, AY0 = LOCK.y0 - 12;
  const AW = LOCK.x1 - LOCK.x0 + 24, AH = LOCK.y1 - LOCK.y0 + 24;
  const wrap = (name, inner) => writeFileSync(join(ADIR, name),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${AX0.toFixed(1)} ${AY0.toFixed(1)} ${AW.toFixed(1)} ${AH.toFixed(1)}" role="img" aria-label="amber avatar — ${name.replace(".svg", "")}, transparent ground">${inner}</svg>`);

  // canon radial ink, white swoosh on top
  {
    const lines = canonicalHairlines();
    wrap("amber-canon.svg", defs("av1") + brandRadial("avink0") +
      mark("av1", `<rect x="${AX0}" y="${AY0}" width="${AW}" height="${AH}" fill="url(#avink0)"/>`, lines));
  }
  // bit8 quantized ink, original white swoosh on top
  {
    const pal = ["#FFE9C7", "#F2C7E2", "#CBE6C9", "#A8DDEA", "#8E7BB8"];
    const r = rng(57021), grid = 7;
    let cells = "";
    for (let x = AX0; x < AX0 + AW; x += grid) {
      for (let y = AY0; y < AY0 + AH; y += grid) {
        const t = radT(x + grid / 2, y + grid / 2);
        let idx = Math.min(4, Math.round(t * 5));
        if (r() < 0.06) idx = Math.min(4, idx + 1);
        cells += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${grid}" height="${grid}" fill="${pal[idx]}"/>`;
      }
    }
    const lines = canonicalHairlines();
    wrap("amber-bit8.svg", defs("av2") + mark("av2", cells, lines));
  }
  // candy prism ink, white swoosh on top
  {
    const g = `<linearGradient id="avink3" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
      `<stop offset="0" stop-color="#F0559C"/><stop offset="0.55" stop-color="#8A4BFF"/><stop offset="1" stop-color="#0FA88A"/></linearGradient>`;
    const lines = canonicalHairlines();
    wrap("amber-candy.svg", defs("av3") + g +
      mark("av3", `<rect x="${AX0}" y="${AY0}" width="${AW}" height="${AH}" fill="url(#avink3)"/>`, lines));
  }
}

// ---------- page ----------
function page() {
  const cells = PLATES.map(pl =>
    `<figure><img src="plates/${String(pl.num).padStart(2, "0")}_${pl.slug}.svg" alt="${pl.slug}">` +
    `<figcaption>${String(pl.num).padStart(2, "0")} · ${pl.slug.replaceAll("_", " ")} — ${pl.note}</figcaption></figure>`).join("");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1">` +
    `<title>plur1bus plates — the amber mark, ten directions</title>` +
    `<style>
      body { margin:0; background:#141416; color:#C9C9CF; font:14px/1.5 Helvetica, Arial, sans-serif; padding:28px 30px 44px; }
      h1 { font-size:15px; letter-spacing:.04em; color:#ECECF2; margin:0 0 4px; font-weight:600; }
      p.sub { margin:0 0 22px; color:#8B8B93; max-width:70ch; }
      .ref { margin:0 0 26px; max-width:620px; }
      .ref img, .grid figure img { width:100%; display:block; border-radius:4px; background:#0D0D0F; }
      figcaption { color:#8B8B93; font-size:12px; margin-top:6px; letter-spacing:.03em; }
      .grid { display:grid; grid-template-columns:repeat(2, minmax(0,620px)); gap:26px 26px; }
      figure { margin:0; }
      h2 { font-size:13px; letter-spacing:.04em; color:#ECECF2; margin:34px 0 4px; font-weight:600; }
      .avatars { display:grid; grid-template-columns:repeat(3, minmax(0,1fr)); gap:26px; margin-top:10px; }
      .checker { display:inline-block; padding:10px 12px; border-radius:4px;
        background:repeating-conic-gradient(#26262b 0% 25%, #19191d 0% 50%); background-size:18px 18px; }
      .checker img { display:block; border-radius:2px; }
      .figrow { display:flex; gap:12px; align-items:flex-end; margin-top:10px; }
    </style></head><body>` +
    `<h1>plur1bus plates — the amber&reg; mark, ten directions</h1>` +
    `<p class="sub">Every study keeps the original Caprasimo glyphs and nine white swoosh paths, widths and opacity. Only the ink treatment changes. Study plates clip the visible swoosh to the letter interiors; the reference preserves the original full-width swoosh.</p>` +
    `<figure class="ref"><img src="plates/reference-original.svg" alt="canonical amber mark, cropped">` +
    `<figcaption>00 · reference — production mark, original full-width swoosh</figcaption></figure>` +
    `<div class="grid">${cells}</div>` +
    `<h2>avatar cuts — transparent ground</h2>` +
    `<p class="sub">The sprite-workflow deliverable: the same locked font and hairlines with no ground plate — ` +
    `alpha-transparent SVGs cropped tight to the letterforms, shown at 128 / 64 / 32 px on a checker so the ` +
    `alpha channel is visible. Drop-in ready for favicon and avatar slots.</p>` +
    `<div class="avatars">` +
    ["amber-canon", "amber-bit8", "amber-candy"].map(n => {
      const cap = { "amber-canon": "canon radial ink", "amber-bit8": "bit8 pixel ink", "amber-candy": "candy prism ink" }[n];
      return `<figure><div class="checker"><img src="plates/avatars/${n}.svg" style="width:128px" alt="${cap}"></div>` +
        `<div class="figrow"><div class="checker"><img src="plates/avatars/${n}.svg" style="width:64px" alt=""></div>` +
        `<div class="checker"><img src="plates/avatars/${n}.svg" style="width:32px" alt=""></div></div>` +
        `<figcaption>${cap} — 128 / 64 / 32 px</figcaption></figure>`;
    }).join("") +
    `</div></body></html>`;
}

mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) rmSync(join(OUT, f), { recursive: true });
p01(); p02(); p03(); p04(); p05(); p06(); p07(); p08(); p09(); p10();
pref();
avatars();
writeFileSync(join(DIR, "all-plates.html"), page());
console.log(`wrote ${PLATES.length} plates + reference + page`);
