// Print the completed BIZ HTMLs to PDF with the Playwright Chromium
// headless shell (invoked as a binary; no Python). The @page rule in each
// document (156mm 234mm) determines the page size, as in the pub5 anlage.
// Every front page is also rendered as a png at one CSS-pixel scale
// (96 dpi = 4/3 x 72 pt), Johann, 2026-11-07: "include a png of every
// front page ... in BIZ"; the folder law carries it beside the pair.
// Usage: node scripts/bp_print.mjs
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, renameSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { OUTPUT_DIR as OUT, BIZ_ROOT } from './paths.mjs';

const ORDER = ['syre', 'speis', 'ragnhild', 'future_nato_weapons', 'norwegianhedge', 'pubhealthcare', 'govt_bergen', 'future_healthcare_os', 'fetat'];
// fetat.html is built by fetat_build.rb straight into the published BIZ
// folder (it owns the svg mark and the traced cover), so its printed
// source is the published copy unless the output dir carries it too.
const FETAT_SOURCE = () => {
  if (existsSync(`${OUT}/fetat/fetat.html`)) return `${OUT}/fetat/fetat.html`;
  if (existsSync(`${BIZ_ROOT}/fetat/fetat.html`)) return `${BIZ_ROOT}/fetat/fetat.html`;
  return null;
};
const CHROME_CANDIDATES = [
  process.env.BIZ_CHROME_BIN,
  process.env.CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  'chrome-headless-shell',
  'chromium',
  'chromium-browser',
  'google-chrome',
  'google-chrome-stable',
].filter(Boolean);

function available(command) {
  if (command.includes('/') || command.includes('\\')) return existsSync(command);
  return spawnSync('which', [command], { stdio: 'ignore' }).status === 0;
}

const CHROME = CHROME_CANDIDATES.find(available);
const AUDIT_PARENT = process.env.BIZ_AUDIT_DIR ? resolve(process.env.BIZ_AUDIT_DIR) : tmpdir();
mkdirSync(AUDIT_PARENT, { recursive: true });
const AUDIT_DIR = mkdtempSync(join(AUDIT_PARENT, 'pub5-biz-pages-'));
if (!CHROME) {
  throw new Error('Chromium/Chrome not found; set BIZ_CHROME_BIN to its executable path.');
}

for (const name of ORDER) {
  let src = `file://${OUT}/${name}/${name}.html`;
  const pdf = `${OUT}/${name}/${name}.pdf`;
  if (name === 'fetat') {
    const s = FETAT_SOURCE();
    if (!s) throw new Error('fetat: no fetat.html on either path; run ruby fetat_build.rb first.');
    src = `file://${s}`;
    mkdirSync(`${OUT}/fetat`, { recursive: true });
  }
  const r = spawnSync(CHROME, [
    '--headless', '--disable-gpu', '--no-sandbox',
    '--no-pdf-header-footer', '--virtual-time-budget=20000',
    `--print-to-pdf=${pdf}`, src,
  ], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`${name}: chromium exited ${r.status}\n${r.stderr}`);
  const pdfinfo = process.env.PDFINFO_BIN || 'pdfinfo';
  const infoResult = spawnSync(pdfinfo, [pdf], { encoding: 'utf8' });
  if (infoResult.error || infoResult.status !== 0) {
    throw new Error(`pdfinfo failed for ${pdf}: ${infoResult.error?.message || infoResult.stderr}`);
  }
  const info = infoResult.stdout || '';
  const size = (info.match(/Page size:\s*([\d.]+ x [\d.]+) pts/) || [])[1];
  const pages = Number((info.match(/Pages:\s*(\d+)/) || [])[1]);
  if (!Number.isInteger(pages) || pages < 1) throw new Error(`${name}: pdfinfo did not report a valid page count`);
  const bytes = statSync(pdf).size;
  console.log(`${name}: ${bytes} bytes, ${pages} pages, ${size} pts`);
  if (size !== '442.08 x 663.12') throw new Error(`${name}: unexpected page size ${size}`);
  const allPages = spawnSync('pdftoppm', [
    '-r', '144', '-png', '-f', '1', '-l', String(pages), pdf, join(AUDIT_DIR, name),
  ], { encoding: 'utf8' });
  if (allPages.status !== 0) throw new Error(`${name}: full-page rasterization failed\n${allPages.stderr}`);
  const pageRasters = readdirSync(AUDIT_DIR)
    .filter(file => file.startsWith(`${name}-`) && file.endsWith('.png'))
    .map(file => ({ file, page: Number(file.match(/-(\d+)\.png$/)?.[1]) }))
    .sort((a, b) => a.page - b.page);
  if (pageRasters.length !== pages || pageRasters.some((row, index) =>
    row.page !== index + 1 || statSync(join(AUDIT_DIR, row.file)).size < 2000
  )) {
    throw new Error(`${name}: expected ${pages} non-empty sequential page renders; found ${pageRasters.length}`);
  }
  const ppm = spawnSync('pdftoppm', ['-r', '96', '-png', '-f', '1', '-l', '1', pdf, `${OUT}/${name}/${name}`], { encoding: 'utf8' });
  if (ppm.status !== 0) throw new Error(`${name}: pdftoppm exited ${ppm.status}\n${ppm.stderr}`);
  // poppler zero-pads the page number to the document's page count
  // (syre-01.png on a 17-page plan, fetat-1.png on a 6-page one)
  const raster = readdirSync(`${OUT}/${name}`).find(f => new RegExp(`^${name}-\\d+\\.png$`).test(f));
  if (!raster) throw new Error(`${name}: pdftoppm produced no front-page png`);
  renameSync(`${OUT}/${name}/${raster}`, `${OUT}/${name}/${name}.png`);
  console.log(`${name}: front page png ${name}.png; all ${pages} pages rasterized at 144 dpi in ${AUDIT_DIR} for visual inspection`);
}
console.log(`done; full-page visual audit renders: ${AUDIT_DIR}`);
