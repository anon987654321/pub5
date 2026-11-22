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
