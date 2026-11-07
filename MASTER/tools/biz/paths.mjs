// Shared paths for the standalone BIZ build tools.
// The anlage lives here, in MASTER/tools, outside the published plan tree
// (BUSPLAN_NO_WORKING_TREES: BIZ carries only the plan folders). Generated
// HTML/PDF files default to the operating system's temporary directory and
// can be redirected explicitly.
import { dirname, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

export const TOOL_DIR = dirname(fileURLToPath(import.meta.url));
export const BIZ_ROOT = resolve(process.env.BIZ_TREE || '/Users/mac/Documents/GitHub/pub5');
export const SOURCE_DIR = resolve(process.env.BIZ_SOURCE_DIR || import.meta.dirname);

export const OUTPUT_DIR = resolve(
  process.env.BIZ_OUT_DIR || resolve(tmpdir(), 'pub5-good-BIZ'),
);
