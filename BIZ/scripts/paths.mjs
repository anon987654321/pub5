// Shared paths for the standalone BIZ build tools.
// Source stays in the repository; generated HTML/PDF files default to the
// operating system's temporary directory and can be redirected explicitly.
import { dirname, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

export const BIZ_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const SOURCE_DIR = resolve(process.env.BIZ_SOURCE_DIR || BIZ_ROOT);
export const OUTPUT_DIR = resolve(
  process.env.BIZ_OUT_DIR || resolve(tmpdir(), 'pub5-good-BIZ'),
);
