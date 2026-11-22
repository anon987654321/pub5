// Print the completed BIZ HTMLs to PDF with the Playwright Chromium
// headless shell (invoked as a binary; no Python). The @page rule in each
// document (156mm 234mm) determines the page size, as in the pub5 anlage.
// Every front page is also rendered as a png at one CSS-pixel scale
// (96 dpi = 4/3 x 72 pt), Johann, 2026-11-07: "include a png of every
// front page ... in BIZ"; the folder law carries it beside the pair.
// Usage: BIZ_CHROME_BIN=/path/to/chrome node BIZ/tools/bp_print.mjs
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, linkSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { OUTPUT_DIR as OUT, BIZ_ROOT, PUBLISHED_INPUTS } from './paths.mjs';

const ORDER = ['syre', 'ragnhild', 'ragnhild_legater', 'nordvakt', 'norwegianfinancial', 'pubhealthcare', 'govt_bergen', 'future_healthcare_os', 'fetat'];
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

function occupied(path) {
  try {
    lstatSync(path);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function sourceInputDigests(name) {
  const declared = PUBLISHED_INPUTS[name];
  if (!declared) throw new Error(`${name}: source-input manifest is missing`);
  const inputs = [...new Set([...declared.html, ...declared.pdf])].sort();
  return Object.fromEntries(inputs.map(input => {
    const path = resolve(BIZ_ROOT, input);
    if (!existsSync(path)) throw new Error(`${name}: declared source input is missing: ${input}`);
    return [input, sha256(path)];
  }));
}

const CHROME = CHROME_CANDIDATES.find(available);
const AUDIT_PARENT = process.env.BIZ_AUDIT_DIR ? resolve(process.env.BIZ_AUDIT_DIR) : tmpdir();
mkdirSync(AUDIT_PARENT, { recursive: true });
const AUDIT_DIR = mkdtempSync(join(AUDIT_PARENT, 'pub5-biz-pages-'));
if (!CHROME) {
  throw new Error('Chromium/Chrome not found; set BIZ_CHROME_BIN to its executable path.');
}

for (const name of ORDER) {
  // The grant guide is a second document in Ragnhild's folder, not the
  // business-plan HTML. Keep its output beside that plan under a distinct
  // basename so neither source nor PDF can overwrite the other.
  const outputDir = name === 'ragnhild_legater' ? `${OUT}/ragnhild` : `${OUT}/${name}`;
  let source = `${OUT}/${name}/${name}.html`;
  if (name === 'fetat') {
    source = FETAT_SOURCE();
    if (!source) throw new Error('fetat: no fetat.html on either path; run ruby fetat_build.rb first.');
  } else if (name === 'ragnhild_legater') {
    source = `${BIZ_ROOT}/ragnhild/ragnhild_legater.html`;
  }
  if (!existsSync(source)) throw new Error(`${name}: source HTML missing: ${source}`);
  const sourceHtmlSha256 = sha256(source);
  const sourceInputsSha256 = sourceInputDigests(name);
  mkdirSync(outputDir, { recursive: true });
  const src = `file://${source}`;
  const pdf = `${outputDir}/${name}.pdf`;
  const frontPng = `${outputDir}/${name}.png`;
  const printReceipt = `${outputDir}/${name}.print.json`;
  const receiptTemp = `${outputDir}/.${name}.print.json.tmp`;
  const numberedPngs = readdirSync(outputDir).filter(file =>
    file.startsWith(`${name}-`) && /^[A-Za-z0-9_-]+-[0-9]+[.]png$/.test(file)
  );
  if (occupied(pdf) || occupied(frontPng) || occupied(printReceipt) ||
      occupied(receiptTemp) || numberedPngs.length) {
    throw new Error(`${name}: output exists; choose a fresh empty BIZ_OUT_DIR rather than replacing an earlier PDF/PNG`);
  }

  const r = spawnSync(CHROME, [
    '--headless', '--disable-gpu', '--no-sandbox',
    '--no-pdf-header-footer', '--virtual-time-budget=20000',
    `--print-to-pdf=${pdf}`, src,
  ], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`${name}: chromium exited ${r.status}\\n${r.stderr}`);

  const pdfinfo = process.env.PDFINFO_BIN || 'pdfinfo';
  const infoResult = spawnSync(pdfinfo, [pdf], { encoding: 'utf8' });
  if (infoResult.error || infoResult.status !== 0) {
    throw new Error(`pdfinfo failed for ${pdf}: ${infoResult.error?.message || infoResult.stderr}`);
  }
  const info = infoResult.stdout || '';
  const size = (info.match(/^Page size:[ \t]*([0-9.]+ x [0-9.]+) pts$/m) || [])[1];
  const pages = Number((info.match(/^Pages:[ \t]*([0-9]+)$/m) || [])[1]);
  if (!Number.isInteger(pages) || pages < 1) throw new Error(`${name}: pdfinfo did not report a valid page count`);
  if (name === 'ragnhild_legater' && pages !== 5) {
    throw new Error(`${name}: five source sheets should print as five pages; found ${pages}`);
  }
  const bytes = statSync(pdf).size;
  console.log(`${name}: ${bytes} bytes, ${pages} pages, ${size} pts`);
  if (size !== '442.08 x 663.12') throw new Error(`${name}: unexpected page size ${size}`);

  const allPages = spawnSync('pdftoppm', [
    '-r', '144', '-png', '-f', '1', '-l', String(pages), pdf, join(AUDIT_DIR, name),
  ], { encoding: 'utf8' });
  if (allPages.status !== 0) throw new Error(`${name}: full-page rasterization failed\\n${allPages.stderr}`);
  const pageRasters = readdirSync(AUDIT_DIR)
    .filter(file => file.startsWith(`${name}-`) && file.endsWith('.png'))
    .map(file => ({ file, page: Number(file.match(/-([0-9]+)[.]png$/)?.[1]) }))
    .sort((a, b) => a.page - b.page);
  if (pageRasters.length !== pages || pageRasters.some((row, index) =>
    row.page !== index + 1 || statSync(join(AUDIT_DIR, row.file)).size < 2000
  )) {
    throw new Error(`${name}: expected ${pages} non-empty sequential page renders; found ${pageRasters.length}`);
  }

  const ppm = spawnSync('pdftoppm', ['-r', '96', '-png', '-f', '1', '-l', '1', pdf, `${outputDir}/${name}`], { encoding: 'utf8' });
  if (ppm.status !== 0) throw new Error(`${name}: pdftoppm exited ${ppm.status}\\n${ppm.stderr}`);
  // Poppler zero-pads the page number to the document's page count
  // (syre-01.png on a 17-page plan, fetat-1.png on a 6-page one).
  const raster = readdirSync(outputDir).find(file =>
    file.startsWith(`${name}-`) && /^[A-Za-z0-9_-]+-[0-9]+[.]png$/.test(file)
  );
  if (!raster) throw new Error(`${name}: pdftoppm produced no front-page png`);
  renameSync(`${outputDir}/${raster}`, frontPng);

  if (sha256(source) !== sourceHtmlSha256 ||
      JSON.stringify(sourceInputDigests(name)) !== JSON.stringify(sourceInputsSha256)) {
    throw new Error(`${name}: a source changed during printing; discard this scratch output and rerun from a fresh BIZ_OUT_DIR`);
  }

  const printRecord = {
    schema: 'biz.print.v2',
    generated_at: new Date().toISOString(),
    document: name,
    source_html: basename(source),
    source_html_sha256: sourceHtmlSha256,
    source_inputs_sha256: sourceInputsSha256,
    pdf: basename(pdf),
    pdf_sha256: sha256(pdf),
    front_png: basename(frontPng),
    front_png_sha256: sha256(frontPng),
    pdf_bytes: statSync(pdf).size,
    front_png_bytes: statSync(frontPng).size,
    page_count: pages,
    page_size_points: size,
    full_page_raster_count: pageRasters.length,
    full_page_raster_bytes: pageRasters.reduce((sum, row) => sum + statSync(join(AUDIT_DIR, row.file)).size, 0),
    human_review: {
      visual: 'NOT_REVIEWED',
      accessibility: 'NOT_REVIEWED'
    }
  };
  writeFileSync(receiptTemp, JSON.stringify(printRecord, null, 2) + String.fromCharCode(10),
                { flag: 'wx', mode: 0o644 });
  try {
    // Hard-link publication is atomic and refuses to replace an existing receipt.
    linkSync(receiptTemp, printReceipt);
  } finally {
    if (occupied(receiptTemp)) unlinkSync(receiptTemp);
  }
  console.log(`${name}: print receipt ${basename(printReceipt)}; visual/accessibility review NOT_REVIEWED`);
  console.log(`${name}: front page png ${name}.png; all ${pages} pages rasterized at 144 dpi in ${AUDIT_DIR} for visual inspection`);
}
console.log(`done; full-page visual audit renders: ${AUDIT_DIR}`);
