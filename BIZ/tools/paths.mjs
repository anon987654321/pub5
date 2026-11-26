// Shared paths for the BIZ build tools.
// One tree since the 2026-11-08 consolidation: BPLANS and MASTER/tools/biz
// folded into BIZ. The build bases (the restored pub5 port documents) live
// beside the tooling in BIZ/tools/<plan>.html; the published pairs the reader
// receives live in BIZ/<plan>/<plan>.html (+ pdf, + svg mark) and are the
// only copies a build output may replace. Generated HTML/PDF files default
// to the operating system's temporary directory and can be redirected
// explicitly; nothing a build writes is published unless the operator moves
// it into a plan folder.
import { dirname, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

export const TOOL_DIR = dirname(fileURLToPath(import.meta.url));

// The BIZ tree itself (the dir holding the plan folders, tools, templates).
export const BIZ_ROOT = process.env.BIZ_TREE
  ? resolve(process.env.BIZ_TREE)
  : resolve(TOOL_DIR, '..');

// The build base of a plan: BIZ/tools/<plan>.html — the editable port copy
// the additions merge into before anything is published.
export const SOURCE_DIR = resolve(TOOL_DIR);

// A plan's published copy: BIZ/<plan>/<plan>.html — the reader-facing pair
// member, printed to the pdf that lives beside it.
export function planBase(plan) {
  return resolve(BIZ_ROOT, plan, `${plan}.html`);
}

export const OUTPUT_DIR = resolve(
  process.env.BIZ_OUT_DIR || resolve(tmpdir(), 'pub5-good-BIZ'),
);

// The source graph for each printed document. Keep it beside the shared path
// contract so the printer records it and the index verifies the same manifest.
// Paths are relative to BIZ_ROOT; html inputs produce the document, pdf inputs
// affect print output. The generated HTML/PDF/PNG are hashed in the receipt too.
const buildInputs = ['tools/bp_build.mjs', 'tools/bp_retemplate.mjs', 'tools/bp_check.mjs', 'tools/paths.mjs'];
const contentInputs = ['tools/plans_a.mjs', 'tools/plans_b.mjs', 'tools/content_add.mjs'];
const printInputs = ['tools/bp_print.mjs', 'tools/paths.mjs'];

function printed(html) {
  return { html, pdf: [...printInputs] };
}

function planInputs(plan) {
  return printed([`tools/${plan}.html`, ...contentInputs, ...buildInputs]);
}

export const PUBLISHED_INPUTS = {
  syre: planInputs('syre'),
  nordvakt: planInputs('nordvakt'),
  norwegianfinancial: planInputs('norwegianfinancial'),
  ragnhild: planInputs('ragnhild'),
  pubhealthcare: planInputs('pubhealthcare'),
  govt_bergen: planInputs('govt_bergen'),
  future_healthcare_os: printed(['tools/future_healthcare_os.html', ...buildInputs]),
  neolimb: printed(['tools/neolimb.html', 'tools/neolimb_proposal.md', ...buildInputs]),
  ragnhild_legater: printed(['ragnhild/ragnhild_legater.html']),
  speis: { html: ['tools/speis.html'], pdf: [] },
  future_nato_weapons: { html: ['tools/future_nato_weapons.html'], pdf: [] },
  norwegianhedge: { html: ['tools/norwegianhedge.html'], pdf: [] },
  fetat: printed(['tools/fetat_build.rb', 'tools/fetat_image.jpg']),
};
