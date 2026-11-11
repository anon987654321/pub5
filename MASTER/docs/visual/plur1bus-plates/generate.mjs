// plur1bus plates — rework: the mark fills the frame, the swoosh is cropped
// around the letters. Every plate extracts the Caprasimo glyph outlines and
// the nine swoosh hairlines live from the logo partial, so the font and the
// swoosh style and lines stay identical to the shipped mark; only the
// material, ground and grade change. Seeded and reproducible.
//
// Usage: node generate.mjs   (writes plates/*.svg and all-plates.html)

import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = dirname(fileURLToPath(import.meta.url));
const OUT = join(DIR, "plates");
const ROOT = join(DIR, "../../../..");
const PARTIAL = join(ROOT, "RAILS/amber/app/views/shared/_logo.html.erb");

const ERB = readFileSync(PARTIAL, "utf8");
const GLYPHS = Object.fromEntries([...ERB.matchAll(/caprasimo-([a-z]+)" d="([^"]+)"/g)].map(m => [m[1], m[2]]));
const TRANSFORMS = Object.fromEntries([...ERB.matchAll(/caprasimo-([a-z]+)" transform="([^"]+)"/g)].map(m => [m[1], m[2]]));
const HAIRLINES = [...ERB.matchAll(/<path stroke="#FFFFFF" stroke-width="([\d.]+)"[^>]*d="([^"]+)"/g)].map(m => [parseFloat(m[1]), m[2]]);

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

// uniform tight stage centred on the lockup
const W = 620, H = 300;
const SX = (LOCK.x0 + LOCK.x1) / 2 - W / 2;
const SY = (LOCK.y0 + LOCK.y1) / 2 - H / 2;
const VB = `${SX.toFixed(1)} ${SY.toFixed(1)} ${W} ${H}`;

// swoosh crop window: hug the letters, exit shortly past the ®
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
function steppedLine(y0, grid) {
  const pts = [];
  for (let x = 50; x <= 950; x += grid / 2) pts.push([x, hairY(y0, x)]);
  return pts
    .filter(p => p[0] >= CX0 && p[0] <= CX1)
    .map(p => `${pts.indexOf(p) === 0 ? "M" : "L"}${(p[0] / grid).toFixed(0) * grid} ${(p[1] / grid).toFixed(0) * grid}`)
    .join(" ");
}

// frozen position of the animated radial ink (reference)
const RADIAL = [500, 250, 560];
const radT = (x, y) => Math.min(1, Math.hypot(x - RADIAL[0], y - RADIAL[1]) / RADIAL[2]);

// seeded rng
function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }

// ---------- svg helpers ----------
let uid = 0;
function defs(id) {
  const glyphs = Object.entries(GLYPHS).map(([g, d]) => `<path id="${id}-${g}" d="${d}"/>`).join("");
  const uses = Object.keys(GLYPHS).map(g => `<use href="#${id}-${g}" transform="${TRANSFORMS[g]}"/>`).join("");
  // clipPath content model takes shapes/use only — a <g> wrapper makes
  // Chromium discard the whole clip (the wordmark vanishes). Children go in bare.
  const mask = `<clipPath id="${id}-text">${uses}</clipPath>`;
  // mask variant: the band MINUS the glyphs — hairlines cropped around the letters
  const around = `<mask id="${id}-around"><rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#fff"/><g fill="#000">${uses}</g></mask>`;
  return `<defs>${glyphs}${mask}${around}</defs>`;
}
const inkG = (id, inner) => `<g clip-path="url(#${id}-text)">${inner}</g>`;
function hairlines(stroke, extra = "", fade = true) {
  let paint = stroke;
  if (fade) {
    const gid = `fade${uid++}`;
    paint = `url(#${gid})`;
    var fg = `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="${CX0}" y1="0" x2="${CX1}" y2="0">` +
      `<stop offset="0" stop-color="${stroke}" stop-opacity="0"/><stop offset="0.1" stop-color="${stroke}" stop-opacity="1"/>` +
      `<stop offset="0.86" stop-color="${stroke}" stop-opacity="1"/><stop offset="1" stop-color="${stroke}" stop-opacity="0"/></linearGradient>`;
  }
  const paths = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="${paint}" stroke-width="${w}"${extra}/>`).join("");
  return (fg || "") + `<g clip-path="url(#crop${uid - 1})">` + paths + "</g>";
}
let cropDefs = "";
function cropDef() {
  cropDefs = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`;
}
function doc(num, slug, title, ground, body, extraDefs = "") {
  const id = `pl${num}`;
  cropDef();
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="${title}">` +
    `<title>${title}</title>` + defs(id) + cropDefs + extraDefs + `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="none"/>` +
    ground + body + `</svg>`;
}
function sparkle(x, y, s, color, opacity = 1) {
  return `<path d="M${x} ${y - s} Q${x} ${y} ${x + s} ${y} Q${x} ${y} ${x} ${y + s} Q${x} ${y} ${x - s} ${y} Q${x} ${y} ${x} ${y - s} Z" fill="${color}" opacity="${opacity}"/>`;
}

const PLATES = [];
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

// ---------- 01 unum stipple — many carriers, one readable form ----------
function p01() {
  const id = "pl1", r = rng(5701);
  // perforation: carriers on the left dissolve into solid ink on the right
  let holes = "";
  for (let gx = LOCK.x0 - 6; gx < LOCK.x1; gx += 4.4) {
    const u = (gx - LOCK.x0) / (LOCK.x1 - LOCK.x0);
    for (let gy = LOCK.y0 - 4; gy < LOCK.y1 + 6; gy += 4.4) {
      if (r() < 0.94 * Math.pow(Math.max(0, 1 - u * 1.7), 1.15)) {
        holes += `<circle cx="${(gx + r() * 3).toFixed(1)}" cy="${(gy + r() * 3).toFixed(1)}" r="${(1.0 + r() * 1.4).toFixed(2)}" fill="#0B0B0B"/>`;
      }
    }
  }
  let sig = "";
  for (let i = 0; i < 6; i++) sig += `<circle cx="${(LOCK.x0 + 18 + r() * 46).toFixed(1)}" cy="${(LOCK.y0 + 40 + r() * 90).toFixed(1)}" r="1.6" fill="#C8F55F"/>`;
  const dots = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#ECECEC" stroke-width="${Math.max(0.8, w)}" stroke-linecap="round" stroke-dasharray="0.1 6"/>`).join("");
  const lines = `<linearGradient id="f1" gradientUnits="userSpaceOnUse" x1="${CX0}" y1="0" x2="${CX1}" y2="0">` +
    `<stop offset="0" stop-color="#ECECEC" stop-opacity="0"/><stop offset="0.12" stop-color="#ECECEC" stop-opacity="0.95"/>` +
    `<stop offset="0.86" stop-color="#ECECEC" stop-opacity="0.95"/><stop offset="1" stop-color="#ECECEC" stop-opacity="0"/></linearGradient>` +
    `<g clip-path="url(#crop${uid})">${dots}</g>`;
  cropDef();
  uid++;
  const out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — many carriers resolve into one readable form">` +
    `<title>amber mark — many carriers resolve into one readable form</title>` + defs("pl1") + cropDefs + lines +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#0B0B0B"/>` +
    inkG("pl1", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#E8E8E6"/>` + holes + sig) + `</svg>`;
  plate(1, "unum_stipple", "many carriers resolve into one readable form", out);
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
  const lines = HAIRLINES.map(([w, d]) => {
    const y0 = parseFloat(d.match(/M50,([\d.]+)/)[1]);
    return `<path d="${steppedLine(y0, grid)}" fill="none" stroke="#FFFFFF" stroke-width="${w}" shape-rendering="crispEdges"/>`;
  }).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const scan = [];
  for (let y = SY; y < SY + H; y += 6) scan.push(`<rect x="${SX}" y="${y}" width="${W}" height="1.4" fill="#000" opacity="0.10"/>`);
  // sprite-palette rail: the five ramp chips + the signal accent + three EMPTY
  // palette slots, the way a sprite sheet ships its 16-color discipline
  let palBar = "";
  [...pal, "#C8F55F"].forEach((c, i) => {
    palBar += `<rect x="${(SX + 20 + i * 16).toFixed(1)}" y="${SY + H - 24}" width="12" height="12" fill="${c}" stroke="#FFFFFF" stroke-opacity="0.28" shape-rendering="crispEdges"/>`;
  });
  for (let k = 6; k < 9; k++) {
    palBar += `<rect x="${SX + 20 + k * 16}" y="${SY + H - 24}" width="12" height="12" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" shape-rendering="crispEdges"/>`;
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — 8-bit bit-reduction with stepped swoosh">` +
    `<title>amber mark — 8-bit bit-reduction with stepped swoosh</title>` + defs("pl2") + crop +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#101013"/>` +
    `<g clip-path="url(#pl2-text)">${cells}${sig}</g>` +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` + scan.join("") + palBar + `</svg>`;
  plate(2, "bit8_pixel", "8-bit bit-reduction — stepped swoosh, sprite palette rail with empty slots", svg);
}

// ---------- 03 dither4 press — 4-bit ordered dither, legible ----------
function p03() {
  const id = "pl3", cell = 6.5, r = rng(5703);
  const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map(row => row.map(v => (v + 0.5) / 16));
  let cells = "";
  for (let x = CX0; x < CX1; x += cell) {
    for (let y = LOCK.y0 - 8; y < LOCK.y1 + 8; y += cell) {
      const cxg = Math.floor(((x - CX0) / cell) % 4 + 4) % 4, cyg = Math.floor(((y - LOCK.y0) / cell) % 4 + 4) % 4;
      const b = bayer[cyg][cxg];
      // normalized tone: 1 at the solid right, 0 at the left edge
      const u = Math.min(1, Math.max(0, (x - LOCK.x0) / (LOCK.x1 - LOCK.x0) * 1.25));
      const v = 0.34 + u * 0.6;
      let fill = null;
      if (v > b + 0.28) fill = "#17130E";
      else if (v > b - 0.1) fill = "#C88A4A";
      if (fill) cells += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${cell}" height="${cell}" fill="${fill}"/>`;
    }
  }
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#17130E" stroke-width="${w}"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — 4-bit ordered dither on paper">` +
    `<title>amber mark — 4-bit ordered dither on paper</title>` + defs("pl3") + crop +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#F2EFE6"/>` +
    `<g clip-path="url(#pl3-text)">${cells}</g>` +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g></svg>`;
  plate(3, "dither4_press", "4-bit ordered dither — the swoosh as one-bit rules", svg);
}

// ---------- 04 signal orbit — motion: the ink roams ----------
function p04() {
  const g = `<radialGradient id="ink4" gradientUnits="userSpaceOnUse" cx="500" cy="250" r="560">` +
    `<animate attributeName="fx" values="500;330;640;500" dur="18s" repeatCount="indefinite"/>` +
    `<animate attributeName="fy" values="250;200;300;250" dur="18s" repeatCount="indefinite"/>` +
    `<stop offset="0" stop-color="#ffb999"/><stop offset="0.33" stop-color="#e6cce6"/>` +
    `<stop offset="0.66" stop-color="#cce6cc"/><stop offset="1" stop-color="#99e6e6"/></radialGradient>`;
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#F4F4F2" stroke-width="${w}"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — the radial ink roams behind the letters">` +
    `<title>amber mark — the radial ink roams behind the letters (motion plate)</title>` + defs("pl4") + crop + g +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#0B0B0B"/>` +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` +
    inkG("pl4", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink4)"/>`) + `</svg>`;
  plate(4, "signal_orbit", "motion — the radial ink roams; everything else is still", svg);
}

// ---------- 05 hue flow — motion: the ink cycles ----------
function p05() {
  const stops = [
    ["#ffb999", "0s"], ["#e6cce6", "-2.5s"], ["#cce6cc", "-5s"], ["#99e6e6", "-7.5s"],
  ];
  const anim = (c, begin) => `<stop offset="${stops.findIndex(s => s[0] === c) / 3}" stop-color="${c}">` +
    `<animate attributeName="stop-color" values="#ffb999;#e6cce6;#cce6cc;#99e6e6;#ffb999" dur="10s" begin="${begin}" repeatCount="indefinite"/></stop>`;
  const g = `<linearGradient id="ink5" gradientUnits="userSpaceOnUse" x1="${CX0}" y1="0" x2="${CX1}" y2="0">` +
    stops.map(([c, b]) => anim(c, b)).join("") + `</linearGradient>`;
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#F4F4F2" stroke-width="${w}"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — the brand gradient flows through the letters">` +
    `<title>amber mark — the brand gradient flows through the letters (motion plate)</title>` + defs("pl5") + crop + g +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#101013"/>` +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` +
    inkG("pl5", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink5)"/>`);
  // palette-cycling rail: the four ramp stops as chips, chevrons between them,
  // and one outlined chip for the wrap-around stop — cycle made visible
  let rail5 = "";
  ["#ffb999", "#e6cce6", "#cce6cc", "#99e6e6"].forEach((c, i) => {
    rail5 += `<rect x="${(SX + 20 + i * 24).toFixed(1)}" y="${SY + H - 24}" width="12" height="12" fill="${c}"/>`;
    if (i < 3) rail5 += `<path d="M${SX + 35 + i * 24} ${SY + H - 19} l3 4 l-3 4" fill="none" stroke="#8B8B93" stroke-width="1.2"/>`;
  });
  rail5 += `<path d="M${SX + 20 + 3 * 24} ${SY + H - 19} l3 4 l-3 4" fill="none" stroke="#8B8B93" stroke-width="1.2"/>` +
    `<rect x="${SX + 20 + 3 * 24 + 9}" y="${SY + H - 24}" width="12" height="12" fill="none" stroke="#ffb999" stroke-opacity="0.85"/>`;
  const svg5 = svg + rail5 + `</svg>`;
  plate(5, "hue_flow", "motion — palette cycling: the shipped ramp cycles through the wordmark", svg5);
}

// ---------- 06 zoetrope frames — motion depicted, not played ----------
function p06() {
  const id = "pl6";
  const ghost = (dx, dy, o) =>
    `<g clip-path="url(#${id}-text)" transform="translate(${dx} ${dy})" opacity="${o}">` +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#F6B26B"/></g>`;
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#241D12" stroke-width="${w}" opacity="0.85"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  let sprockets = "";
  for (let x = SX + 14; x < SX + W - 10; x += 22) {
    sprockets += `<rect x="${x}" y="${SY + 8}" width="9" height="6" fill="#241D12" opacity="0.55"/>`;
    sprockets += `<rect x="${x}" y="${SY + H - 14}" width="9" height="6" fill="#241D12" opacity="0.55"/>`;
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — onion-skin frames of the wordmark stepping along the swoosh">` +
    `<title>amber mark — onion-skin frames of the wordmark stepping along the swoosh</title>` + defs("pl6") + crop +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#F6F1E3"/>` + sprockets +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` +
    ghost(-16, -10, 0.14) + ghost(-8, -5, 0.3) +
    inkG("pl6", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#E8833A"/>`);
  // sprite-sheet frame tags: filled chip = the live frame, outlined chips = the
  // onion ghosts, chevrons stepping between them, tick ruler underneath
  let tags = "";
  for (let i = 0; i < 3; i++) {
    tags += (i === 0)
      ? `<rect x="${SX + 20 + i * 26}" y="${SY + H - 26}" width="16" height="13" fill="#E8833A" stroke="#241D12"/>`
      : `<rect x="${SX + 20 + i * 26}" y="${SY + H - 26}" width="16" height="13" fill="none" stroke="#241D12" stroke-opacity="0.65"/>`;
    if (i < 2) tags += `<path d="M${SX + 39 + i * 26} ${SY + H - 21} l3 3.5 l-3 3.5" fill="none" stroke="#241D12" stroke-width="1.2"/>`;
  }
  for (let k = 0; k < 9; k++) tags += `<rect x="${SX + 20 + k * 9}" y="${SY + H - 9}" width="1.4" height="4" fill="#241D12" opacity="0.5"/>`;
  const svg6 = svg + tags + `</svg>`;
  plate(6, "zoetrope_frames", "sprite-sheet frames — live frame tagged, onion ghosts, tick ruler", svg6);
}

// ---------- 07 starlight comet — shooting stars, sparkles ----------
function p07() {
  const id = "pl7", r = rng(5707);
  const g = `<linearGradient id="ink7" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
    `<stop offset="0" stop-color="#F6F8FF"/><stop offset="1" stop-color="#9FAEE0"/></linearGradient>`;
  let stars = "";
  for (let i = 0; i < 26; i++) {
    stars += `<circle cx="${(SX + 8 + r() * (W - 16)).toFixed(1)}" cy="${(SY + 8 + r() * 66).toFixed(1)}" r="${(0.5 + r() * 0.8).toFixed(2)}" fill="#FFF" opacity="${(0.25 + r() * 0.5).toFixed(2)}"/>`;
  }
  // one shooting star inside the crop band, above the wordmark
  const mx = SX + 90, my = SY + 34, ex = LOCK.x1 - 30, ey = LOCK.y0 - 16;
  const trail = `<linearGradient id="trail7" gradientUnits="userSpaceOnUse" x1="${mx}" y1="${my}" x2="${ex}" y2="${ey}">` +
    `<stop offset="0" stop-color="#FFF" stop-opacity="0"/><stop offset="1" stop-color="#FFF" stop-opacity="0.95"/></linearGradient>`;
  const comet = `<line x1="${mx}" y1="${my}" x2="${ex}" y2="${ey}" stroke="url(#trail7)" stroke-width="1.6"/>` + sparkle(ex, ey, 6.5, "#FFFFFF", 0.98);
  const tips = HAIRLINES.slice(6).map(([w, d]) => {
    const y0 = parseFloat(d.match(/M50,([\d.]+)/)[1]);
    return sparkle(CX1 - 8, hairY(y0, CX1 - 8) - 6, 3 + w * 0.8, "#FFFFFF", 0.9);
  }).join("");
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#FFFFFF" stroke-width="${w}" opacity="0.92"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — comet trails and shooting stars around the wordmark">` +
    `<title>amber mark — comet trails and shooting stars around the wordmark</title>` + defs("pl7") + crop + g + trail +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#0B1020"/>` + stars +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` +
    inkG("pl7", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink7)"/>`) +
    comet + tips + `</svg>`;
  plate(7, "starlight_comet", "the hairlines exit as comet trails with star heads", svg);
}

// ---------- 08 pony rainbow — pizzazz on the cropped swoosh ----------
function p08() {
  const id = "pl8";
  const bands = [
    [SY, 96, "#FFE3F0"], [SY + 96, 108, "#FFF6E8"], [SY + 204, 96, "#DFF5E4"],
  ].map(([y, h, c]) => `<rect x="${SX}" y="${y}" width="${W}" height="${h}" fill="${c}"/>`).join("");
  // rainbow arc cropped by the frame, rising behind the wordmark
  const rcx = (LOCK.x0 + LOCK.x1) / 2, rcy = LOCK.y1 + 330;
  const cols = ["#FF6E6E", "#FFA25C", "#FFE45C", "#7DDB8A", "#5CC8FF", "#9A7DFF"];
  const rainbow = cols.map((c, i) =>
    `<circle cx="${rcx}" cy="${rcy}" r="${330 - 6 - i * 6.5}" fill="none" stroke="${c}" stroke-width="6" opacity="0.75"/>`).join("");
  const g = `<linearGradient id="ink8" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
    `<stop offset="0" stop-color="#F0559C"/><stop offset="0.55" stop-color="#8A4BFF"/><stop offset="1" stop-color="#0FA88A"/></linearGradient>`;
  // pixel pony standing on the widest hairline just past the ®
  const ponyX = CX1 - 66, ponyY = hairY(238, ponyX) - 40, cell = 3.4;
  const rows = ["..MM..MM....", "..MMMMMMM...", "...MMMMMMM..", "WW..MMMMMM..", "WWW.BBBBB...", "WW.BBBBBB.BB", "...BBB.BB.BB", "...BB...BB.B", "...H....H.HH", "..HH....HHHH"];
  const cmap = { M: "#FFFFFF", B: "#FF8AC2", W: "#FFC8E8", H: "#3A2440" };
  let pony = "";
  rows.forEach((row, ry) => [...row].forEach((ch, rx) => {
    if (cmap[ch]) pony += `<rect x="${(ponyX + rx * cell).toFixed(1)}" y="${(ponyY + ry * cell).toFixed(1)}" width="${cell}" height="${cell}" fill="${cmap[ch]}"/>`;
  }));
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#FFFFFF" stroke-width="${w}" opacity="0.95"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — candy ink, rainbow arc behind, pixel pony on the swoosh">` +
    `<title>amber mark — candy ink, rainbow arc behind, pixel pony on the swoosh</title>` + defs("pl8") + crop + g +
    bands + `<g clip-path="url(#crop${uid - 1})">${rainbow}</g>` +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` +
    inkG("pl8", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink8)"/>`) +
    pony + sparkle(SX + 60, SY + 46, 5, "#FFFFFF", 0.95) + sparkle(CX1 - 22, LOCK.y0 - 20, 4, "#FFFFFF", 0.9) + `</svg>`;
  plate(8, "pony_rainbow", "rainbow cropped behind the mark; the pony stands on the swoosh", svg);
}

// ---------- 09 grade teal/amber — explicit cinematic grade ----------
function p09() {
  const id = "pl9";
  const g = `<linearGradient id="ink9" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
    `<stop offset="0" stop-color="#FBD1A2"/><stop offset="1" stop-color="#E89A56"/></linearGradient>`;
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#F7EDE0" stroke-width="${w}" opacity="0.9"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const ramp = `<linearGradient id="ramp9" x1="0" y1="0" x2="1" y2="0">` +
    `<stop offset="0" stop-color="#0E2B33"/><stop offset="1" stop-color="#F2A65A"/></linearGradient>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — teal shadows, amber highlights; the grade is explicit">` +
    `<title>amber mark — teal shadows, amber highlights; the grade is explicit</title>` + defs("pl9") + crop + g + ramp +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#0E2B33"/>` +
    `<g clip-path="url(#crop${uid - 1})">${lines}</g>` +
    inkG("pl9", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink9)"/>`) +
    `<rect x="${SX + 24}" y="${SY + H - 26}" width="96" height="8" fill="url(#ramp9)" opacity="0.9"/>` + `</svg>`;
  plate(9, "grade_teal_amber", "explicit grade — teal ground, amber ink, grade ramp chip", svg);
}

// ---------- 10 duotone riso — hairlines cropped AROUND the glyphs ----------
function p10() {
  const id = "pl10";
  const ghost = inkG("pl10", `<rect x="${SX + 3}" y="${SY + 2}" width="${W}" height="${H}" fill="#FF5A3C" opacity="0.55"/>`);
  const main = inkG("pl10", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#1D2A5C"/>`);
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#50630A" stroke-width="${w}"/>`).join("");
  const crop = `<clipPath id="crop${uid}"><rect x="${CX0}" y="${SY}" width="${CX1 - CX0}" height="${H}"/></clipPath>`; uid++;
  const sig = `<g clip-path="url(#pl10-text)"><circle cx="${LOCK.x0 + 34}" cy="${LOCK.y0 + 52}" r="2.2" fill="#C8F55F"/>` +
    `<circle cx="${LOCK.x0 + 52}" cy="${LOCK.y0 + 96}" r="1.7" fill="#C8F55F"/>` +
    `<circle cx="${LOCK.x0 + 30}" cy="${LOCK.y0 + 120}" r="1.5" fill="#C8F55F"/></g>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="amber mark — riso duotone; the hairlines weave around the letterforms">` +
    `<title>amber mark — riso duotone; the hairlines weave around the letterforms</title>` + defs("pl10") + crop +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#F5F1E6"/>` +
    `<g clip-path="url(#crop${uid - 1})">${ghost}${main}</g>` +
    `<g clip-path="url(#crop${uid - 1})" mask="url(#pl10-around)">${lines}</g>` + sig + `</svg>`;
  plate(10, "duotone_riso", "the hairlines are masked out of the glyphs — cropped around the letters", svg);
}

// ---------- reference (canonical mark, tight stage) ----------
function pref() {
  const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="#FFFFFF" stroke-width="${w}"/>`).join("");
  cropDef();
  const out = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VB}" role="img" aria-label="canonical amber mark">` +
    `<title>canonical amber mark — ink frozen, hairlines cropped around the letters</title>` + defs("pl0") + cropDefs +
    brandRadial("ink0") +
    `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="#0B0B0B"/>` +
    `<g clip-path="url(#crop${uid})">${lines}</g>` +
    inkG("pl0", `<rect x="${SX}" y="${SY}" width="${W}" height="${H}" fill="url(#ink0)"/>`) + `</svg>`;
  writeFileSync(join(OUT, "reference-original.svg"), out);
}

// ---------- avatar cuts — transparent ground, sprite-sheet sizes ----------
// The operator's reference workflow ships avatar-size variants with the
// background removed. Same rule here: identical glyph outlines and hairline
// family, no ground rect — alpha-transparent SVGs cropped tight to the lockup,
// so they can sit on any surface at 128 / 64 / 32 px.
function avatars() {
  const ADIR = join(OUT, "avatars");
  mkdirSync(ADIR, { recursive: true });
  const AX0 = CX0;
  // vertical extent must cover the hairline crests (base curve rises to y0-80)
  const y0s = HAIRLINES.map(([w, d]) => parseFloat(d.match(/M50,([\d.]+)/)[1]));
  const hairTop = Math.min(...y0s) - 83, hairBot = Math.max(...y0s) + 23;
  const AY0 = Math.min(LOCK.y0, hairTop) - 12;
  const AW = CX1 - CX0, AH = Math.max(LOCK.y1, hairBot) - AY0 + 12;
  const fade = (gid, stroke) => `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="${CX0}" y1="0" x2="${CX1}" y2="0">` +
    `<stop offset="0" stop-color="${stroke}" stop-opacity="0"/><stop offset="0.1" stop-color="${stroke}" stop-opacity="1"/>` +
    `<stop offset="0.86" stop-color="${stroke}" stop-opacity="1"/><stop offset="1" stop-color="${stroke}" stop-opacity="0"/></linearGradient>`;
  const cropAv = `<clipPath id="avcrop"><rect x="${CX0}" y="${AY0}" width="${AW}" height="${AH}"/></clipPath>`;
  const wrap = (name, inner) => writeFileSync(join(ADIR, name),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${AX0.toFixed(1)} ${AY0.toFixed(1)} ${AW.toFixed(1)} ${AH.toFixed(1)}" role="img" aria-label="amber avatar — ${name.replace(".svg", "")}, transparent ground">${cropAv}${inner}</svg>`);

  // canon radial ink
  {
    const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="url(#avf1)" stroke-width="${w}"/>`).join("");
    wrap("amber-canon.svg", defs("av1") + fade("avf1", "#FFFFFF") + brandRadial("avink0") +
      `<g clip-path="url(#avcrop)">${lines}</g>` +
      inkG("av1", `<rect x="${AX0}" y="${AY0}" width="${AW}" height="${AH}" fill="url(#avink0)"/>`));
  }
  // bit8 quantized ink, stepped hairlines
  {
    const pal = ["#FFE9C7", "#F2C7E2", "#CBE6C9", "#A8DDEA", "#8E7BB8"];
    const r = rng(57021), grid = 7;
    let cells = "";
    for (let x = CX0; x < CX1; x += grid) {
      for (let y = AY0; y < AY0 + AH; y += grid) {
        const t = radT(x + grid / 2, y + grid / 2);
        let idx = Math.min(4, Math.round(t * 5));
        if (r() < 0.06) idx = Math.min(4, idx + 1);
        cells += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${grid}" height="${grid}" fill="${pal[idx]}"/>`;
      }
    }
    const lines = HAIRLINES.map(([w, d]) => {
      const y0 = parseFloat(d.match(/M50,([\d.]+)/)[1]);
      return `<path d="${steppedLine(y0, grid)}" fill="none" stroke="#FFFFFF" stroke-width="${w}" shape-rendering="crispEdges"/>`;
    }).join("");
    wrap("amber-bit8.svg", defs("av2") +
      `<g clip-path="url(#avcrop)">${lines}</g>` +
      inkG("av2", cells));
  }
  // candy prism ink
  {
    const g = `<linearGradient id="avink3" gradientUnits="userSpaceOnUse" x1="0" y1="${LOCK.y0}" x2="0" y2="${LOCK.y1}">` +
      `<stop offset="0" stop-color="#F0559C"/><stop offset="0.55" stop-color="#8A4BFF"/><stop offset="1" stop-color="#0FA88A"/></linearGradient>`;
    const lines = HAIRLINES.map(([w, d]) => `<path d="${d}" fill="none" stroke="url(#avf3)" stroke-width="${w}"/>`).join("");
    wrap("amber-candy.svg", defs("av3") + fade("avf3", "#FFFFFF") + g +
      `<g clip-path="url(#avcrop)">${lines}</g>` +
      inkG("av3", `<rect x="${AX0}" y="${AY0}" width="${AW}" height="${AH}" fill="url(#avink3)"/>`));
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
    `<p class="sub">Every plate is cropped to the lockup — the wordmark fills the frame and the nine ` +
    `swoosh hairlines fade in at the a, exit just past the &reg;, and thread behind or around the glyphs. ` +
    `Font and swoosh geometry are extracted live from the shipped partial. ` +
    `Plate 02 ships a sprite palette rail with empty slots, plate 05 is palette cycling, ` +
    `plate 06 tags its frames like a sprite sheet.</p>` +
    `<figure class="ref"><img src="plates/reference-original.svg" alt="canonical amber mark, cropped">` +
    `<figcaption>00 · reference — canonical mark on the tight stage</figcaption></figure>` +
    `<div class="grid">${cells}</div>` +
    `<h2>avatar cuts — transparent ground</h2>` +
    `<p class="sub">The sprite-workflow deliverable: the same locked font and hairlines with no ground plate — ` +
    `alpha-transparent SVGs cropped tight to the lockup, shown at 128 / 64 / 32 px on a checker so the ` +
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
