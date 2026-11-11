// Independent BIZ output verification. Common Laws run through MASTER's
// canonical scanner; this file owns only the business-plan print contract and
// the financial arithmetic re-read from the published HTML.
// Usage: node BIZ/tools/bp_check.mjs
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { OUTPUT_DIR as OUT, BIZ_ROOT } from './paths.mjs';

const ORDER = ['syre', 'speis', 'ragnhild', 'future_nato_weapons', 'norwegianhedge', 'pubhealthcare', 'govt_bergen', 'future_healthcare_os'];
const fails = [];
const notes = [];
const ROW4 = /<tr><td>([^<]+)<\\/td><td>([^<]*)<\\/td><td>([^<]*)<\\/td><td>([^<]*)<\\/td><\\/tr>/g;
const ROW4_ONE = new RegExp(ROW4.source);

function parseNum(value) {
  const number = Number.parseFloat(
    value.replaceAll('−', '-').replaceAll(' ', '').replaceAll('\\u202f', '')
      .replaceAll('%', '').replace(',', '.')
  );
  if (!Number.isFinite(number)) throw new Error(`not a number: ${JSON.stringify(value)}`);
  return number;
}

// tfoot values for a 4-cell budget table: [2026, 2027, 2028].
function footVals(tableHtml) {
  const inner = tableHtml.match(/<tfoot>([\\s\\S]*?)<\\/tfoot>/);
  if (!inner) return null;
  const cap = ROW4_ONE.exec(inner[1]);
  return cap ? [cap[2], cap[3], cap[4]] : null;
}

const files = ORDER.map(plan => resolve(OUT, plan, `${plan}.html`));
const masterOperator = resolve(BIZ_ROOT, '..', 'MASTER', 'bin', 'operator');
const lawRun = spawnSync(masterOperator, ['lint', ...files], {
  cwd: BIZ_ROOT,
  encoding: 'utf8',
  timeout: 900_000,
  maxBuffer: 16 * 1024 * 1024,
});
const lawOutput = [lawRun.stdout, lawRun.stderr].filter(Boolean).join('\\n').trim();
if (lawRun.error) {
  fails.push(`MASTER Law scan could not start: ${lawRun.error.message}`);
} else if (lawRun.status !== 0) {
  fails.push(`MASTER Law scan failed (exit ${lawRun.status}): ${lawOutput.slice(-6_000) || 'no output'}`);
} else {
  notes.push(`MASTER Laws: ${files.length} plan documents checked`);
}

for (const plan of ORDER) {
  const file = resolve(OUT, plan, `${plan}.html`);
  let src;
  try {
    src = (await import('node:fs')).readFileSync(file, 'utf8');
  } catch (error) {
    fails.push(`${plan}: cannot read output: ${error.message}`);
    continue;
  }
  const body = src.replace(/base64,[^"']+/g, '');
  const add = message => fails.push(`${plan}: ${message}`);

  // The plan's own mark is artwork, not a typeface for semantic headings.
  const sections = [...src.matchAll(/<section id="([^"]+)"/g)].length;
  if (sections !== 8) add(`sections: ${sections} (expected 8)`);
  const fonts = [...src.matchAll(/@font-face\\s*\\{/g)].length;
  if (plan === 'ragnhild') {
    if (fonts !== 1) add(`font-face: ${fonts} (expected 1: the Nosifer wordmark)`);
    if (!/class="mark-brand">Ragnhilds<\\//.test(body)) add('mark-brand: wordmark missing');
    if (/(?:^|\\})\\s*h[1-4][^{]*\\{[^}]*Nosifer/.test(body)) add('wordmark: Nosifer used on a semantic heading');
  } else if (fonts !== 0) {
    add(`font-face: ${fonts} (expected 0: Google Fonts carries the faces)`);
  }

  // BUSPLAN_TEMPLATE_BOB2: the eight documents share bob2's tokens and one
  // hefte contract, while each retains its own brand mark and content.
  if (!/--color-link:\\s*#005f73/i.test(src)) add('bob2: link token missing');
  if (!/--font-text:\\s*"Source Serif 4"/.test(src)) add('bob2: --font-text token missing');
  if (!/--font-heading:\\s*"EB Garamond"/.test(src)) add('bob2: --font-heading token missing');
  if (!/family=Source\\+Serif\\+4/.test(src)) add('bob2: Source Serif 4 not on the fonts link');
  if (!/family=EB\\+Garamond/.test(src)) add('bob2: EB Garamond not on the fonts link');
  if (!/header\\.cover/.test(src)) add('bob2: header.cover missing');
  if (!/@page\\s*\\{[^}]*size:\\s*156mm 234mm/s.test(src)) add('bob2: hefte page size missing');
  if (!/@bottom-center\\s*\\{[^}]*content:\\s*counter\\(page\\)/s.test(src)) add('bob2: folio missing');
  if (!/@bottom-center\\s*\\{[^}]*font:\\s*0\\.75rem\\/1\\.4 var\\(--font-heading\\)/s.test(src)) add('bob2: folio face is not EB Garamond');
  if (!/@page :first\\s*\\{\\s*margin-top:\\s*0;\\s*\\}/.test(src)) add('bob2: first-page margin rule missing');
  if (/body\\s*\\{\\s*margin:\\s*0;\\s*\\}/.test(src)) add('bob2: print body margin pinned to 0');
  if (!/header\\.cover\\s*\\{\\s*min-height:\\s*221mm;\\s*\\}/.test(src)) add('bob2: cover-as-page rule missing');
  if (!/class="toc" aria-label="Innhold"/.test(src)) add('bob2: toc missing');
  if (/--paper:|--ink:|--accent:|poise v2|cover revision 2026-11/.test(src)) add('bob2: archive-skin token or poise stylesheet still present');
  if (/class="kicker"/.test(body)) add('cover: kicker still present');
  if (!/Satt i Source Serif 4/.test(body)) add('bob2: colophon does not name the skin');
  if (plan === 'govt_bergen') {
    if (!/class="mark mark-plain">Bergens Selvstyreparti<\\//.test(body)) add('cover: plain party mark missing');
    if (/background-clip:\\s*text/.test(body)) add('cover: gradient wordmark still present');
  }

  // Arithmetic is independently re-read from the generated HTML, never copied
  // from the build's in-memory inputs.
  const resultTable = body.match(/<caption>Resultatbudsjett[^<]*<\\/caption>[\\s\\S]*?<\\/table>/);
  if (resultTable) {
    const tbody = resultTable[0].match(/<tbody>([\\s\\S]*?)<\\/tbody>/);
    const foot = footVals(resultTable[0]);
    const rows = tbody ? [...tbody[1].matchAll(ROW4)].map(row => [row[1], row[2], row[3], row[4]]) : [];
    if (!foot || rows.length < 4) add('inconclusive: resultatbudsjett rows/tfoot not parsed');
    else for (let column = 0; column < 3; column++) {
      const income = parseNum(rows[0][column + 1]);
      const cost = parseNum(rows[1][column + 1]);
      const operating = parseNum(rows[2][column + 1]);
      const finance = parseNum(rows[3][column + 1]);
      const beforeTax = parseNum(foot[column]);
      if (Math.abs(income + cost - operating) > 0.011) add(`resultat col${column}: driftsresultat ${income + cost} ≠ ${operating}`);
      if (Math.abs(operating + finance - beforeTax) > 0.011) add(`resultat col${column}: før skatt ${operating + finance} ≠ ${beforeTax}`);
    }
  } else add('resultatbudsjett: table missing');

  const liquidity = body.match(/<caption>Likviditetsbudsjett[^<]*<\\/caption>[\\s\\S]*?<\\/table>/);
  if (liquidity) {
    const tbody = liquidity[0].match(/<tbody>([\\s\\S]*?)<\\/tbody>/);
    const foot = footVals(liquidity[0]);
    const rows = tbody ? [...tbody[1].matchAll(ROW4)].map(row => [row[1], row[2], row[3], row[4]]) : [];
    if (!foot || rows.length === 0) add('inconclusive: likviditetsbudsjett rows/tfoot not parsed');
    else for (let column = 0; column < 3; column++) {
      const total = rows.reduce((sum, row) => sum + parseNum(row[column + 1]), 0);
      if (Math.abs(total - parseNum(foot[column])) > 0.011) add(`likviditet col${column}: sum ${total} ≠ ${foot[column]}`);
      if (column < 2 && rows[0][column + 2] !== undefined &&
          Math.abs(parseNum(foot[column]) - parseNum(rows[0][column + 2])) > 0.011) {
        add(`likviditet: saldo ${column}→${column + 1} breaks continuity`);
      }
    }
  } else add('likviditetsbudsjett: table missing');

  const financing = body.match(/<caption>Bevegelsens finansiering[^<]*<\\/caption>[\\s\\S]*?<\\/table>/);
  if (financing) {
    const tbody = financing[0].match(/<tbody>([\\s\\S]*?)<\\/tbody>/);
    const foot = financing[0].match(/<tfoot>([\\s\\S]*?)<\\/tfoot>/);
    const caption = foot ? /<tr><td>([^<]+)<\\/td><td>([^<]*)<\\/td><\\/tr>/.exec(foot[1]) : null;
    const rows = tbody ? [...tbody[1].matchAll(/<tr><td>([^<]+)<\\/td><td>([^<]*)<\\/td><\\/tr>/g)].map(row => row[2]) : [];
    if (!caption || rows.length === 0) add('inconclusive: finansieringstabell rows/tfoot not parsed');
    else {
      const sum = rows.reduce((total, value) => total + parseNum(value), 0);
      if (Math.abs(sum - parseNum(caption[2])) > 0.011) add(`finansiering: sum ${sum} ≠ ${caption[2]}`);
      notes.push(`${plan}: finansiering sum ${sum} = ${caption[2]}`);
    }
  } else add('finansieringstabell: table missing');

  notes.push(`${plan}: sections ${sections}, fonts ${fonts}, chars ${src.length}`);
}

console.log(notes.join('\\n'));
console.log('=== FAILS ===');
console.log(fails.length ? fails.join('\\n') : 'NONE');
if (fails.length) process.exitCode = 1;
