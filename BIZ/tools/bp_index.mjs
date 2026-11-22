// Generate BIZ/index.html from the active portfolio and each financing table.
// The amount is the explicit Innovasjon Norge row only, never project capital.
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { BIZ_ROOT } from './paths.mjs';

const ACTIVE = [
  ['syre', 'SYRE™', '3D-printede sko', 'Environment & Sustainability'],
  ['ragnhild', 'Ragnhild', 'begravelsesbyrå med Karaokekiste og Diskokiste', 'Social Innovation'],
  ['pubhealthcare', 'pub.healthcare', 'helseberedskap og autonome sykehusprosesser', 'Health'],
  ['govt_bergen', 'Bergen Selvstyreparti', 'lokal medvirkning og forvaltningsteknologi', 'Civic Tech'],
  ['future_healthcare_os', 'Fremtidens helse-OS', 'OpenBSD-disiplin, Rails og etterprøvbar helseforvaltning', 'Health + Infrastructure'],
];
const DRAFTS = [
  ['nordvakt', 'NORDVAKT Arctic Systems (arbeidsnavn)', 'maritim situasjonsforståelse og dataintegrasjon i nordområdene', 'Maritime + Space'],
  ['norwegianfinancial', 'Norwegian Financial (arbeidsnavn)', 'partnerbasert digitalbankplattform, PWA og åpen bank', 'FinTech'],
];
const GUIDES = [
  ['ragnhild/ragnhild_legater', 'Ragnhild Mæhle — søknadsveiledning', 'Kildebasert plan for utstillingsstøtte og kunstnerstipend; veiledning, ikke en innsendt søknad eller et tilsagn'],
];
const ARCHIVE = [
  ['speis', 'SPEIS'],
  ['future_nato_weapons', 'Fremtidens NATO-våpen'],
  ['norwegianhedge', 'Norwegian Hedge — historisk kvantkonsept'],
  ['fetat', 'FETAT — Familieetaten'],
  ['ai3', 'AI³ — arkiv'],
];

const LISTED_PAIRS = new Set([...ACTIVE, ...ARCHIVE].map(([key]) => key));
const TEMPLATE_NAMES = ['bob', 'bob2', 'bob3'];

function verifyIndexInventory() {
  const excluded = new Set(['__templates', 'research', 'tools']);
  const actualPairs = readdirSync(BIZ_ROOT, { withFileTypes: true })
    .filter(entry => entry.isDirectory() || entry.isSymbolicLink())
    .map(entry => entry.name)
    .filter(name => !excluded.has(name))
    .sort();
  const unlisted = actualPairs.filter(name => !LISTED_PAIRS.has(name));
  const missing = [...LISTED_PAIRS].filter(name => !actualPairs.includes(name));
  if (unlisted.length || missing.length) {
    throw new Error('BIZ index inventory mismatch; unlisted directories: ' +
      (unlisted.join(', ') || 'none') + '; missing directories: ' + (missing.join(', ') || 'none'));
  }

  const templateDirectory = `${BIZ_ROOT}/__templates`;
  const templateFiles = readdirSync(templateDirectory)
    .filter(name => /\.(?:html|pdf)$/i.test(name));
  const templateBases = [...new Set(templateFiles.map(name => name.replace(/\.(?:html|pdf)$/i, '')))].sort();
  const expected = [...TEMPLATE_NAMES].sort();
  const unexpected = templateBases.filter(name => !expected.includes(name));
  const absent = expected.filter(name => !templateBases.includes(name));
  const unpaired = templateBases.filter(name =>
    !templateFiles.includes(name + '.html') || !templateFiles.includes(name + '.pdf')
  );
  if (unexpected.length || absent.length || unpaired.length) {
    throw new Error('BIZ template inventory mismatch; unexpected: ' +
      (unexpected.join(', ') || 'none') + '; missing: ' + (absent.join(', ') || 'none') +
      '; unpaired: ' + (unpaired.join(', ') || 'none'));
  }
}

function formatNok(value) {
  return new Intl.NumberFormat('nb-NO', { maximumFractionDigits: 0 }).format(value);
}
function fundingAsk(path) {
  const html = readFileSync(path, 'utf8');
  const table = html.match(/<caption>Bevegelsens finansiering[^<]*<\/caption>[\s\S]*?<\/table>/);
  if (!table) throw new Error(path + ': financing table missing');
  const rows = [...table[0].matchAll(/<tr><td>([^<]+)<\/td><td>([^<]*)<\/td><\/tr>/g)];
  const matches = rows.filter(row => /Innovasjon Norge/i.test(row[1]));
  if (matches.length > 1) throw new Error(path + ': duplicate Innovasjon Norge rows');
  if (!matches.length) return 0;
  const raw = matches[0][2].replaceAll(' ', '').replaceAll(String.fromCharCode(0x202f), '').replace(',', '.');
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) throw new Error(path + ': invalid grant amount ' + raw);
  return Math.round(value);
}
const FRESHNESS_INPUTS = {
  syre: ['tools/syre.html', 'tools/plans_a.mjs', 'tools/plans_b.mjs', 'tools/content_add.mjs', 'tools/bp_build.mjs', 'tools/bp_retemplate.mjs', 'tools/bp_check.mjs', 'tools/bp_print.mjs'],
  ragnhild: ['tools/ragnhild.html', 'tools/plans_a.mjs', 'tools/plans_b.mjs', 'tools/content_add.mjs', 'tools/bp_build.mjs', 'tools/bp_retemplate.mjs', 'tools/bp_check.mjs', 'tools/bp_print.mjs'],
  pubhealthcare: ['tools/pubhealthcare.html', 'tools/plans_a.mjs', 'tools/plans_b.mjs', 'tools/content_add.mjs', 'tools/bp_build.mjs', 'tools/bp_retemplate.mjs', 'tools/bp_check.mjs', 'tools/bp_print.mjs'],
  govt_bergen: ['tools/govt_bergen.html', 'tools/plans_a.mjs', 'tools/plans_b.mjs', 'tools/content_add.mjs', 'tools/bp_build.mjs', 'tools/bp_retemplate.mjs', 'tools/bp_check.mjs', 'tools/bp_print.mjs'],
  future_healthcare_os: ['tools/future_healthcare_os.html', 'tools/bp_build.mjs', 'tools/bp_retemplate.mjs', 'tools/bp_check.mjs', 'tools/bp_print.mjs'],
  speis: ['tools/speis.html', 'tools/bp_print.mjs'],
  future_nato_weapons: ['tools/future_nato_weapons.html', 'tools/bp_print.mjs'],
  norwegianhedge: ['tools/norwegianhedge.html', 'tools/bp_print.mjs'],
  fetat: ['tools/fetat_build.rb', 'tools/fetat_image.jpg', 'tools/bp_print.mjs'],
};

function requirePair(key) {
  const html = `${BIZ_ROOT}/${key}/${key}.html`;
  const pdf = `${BIZ_ROOT}/${key}/${key}.pdf`;
  for (const [ext, path] of [['html', html], ['pdf', pdf]]) {
    if (!existsSync(path)) throw new Error(key + ': published ' + ext + ' missing');
  }

  const htmlTime = statSync(html).mtimeMs;
  const pdfTime = statSync(pdf).mtimeMs;
  if (pdfTime < htmlTime) {
    throw new Error(key + ': published PDF is older than its HTML; rerun the print and review step');
  }

  const inputs = FRESHNESS_INPUTS[key] || [];
  const stale = inputs.filter(input => {
    const source = `${BIZ_ROOT}/${input}`;
    if (!existsSync(source)) throw new Error(key + ': freshness source missing: ' + input);
    return statSync(source).mtimeMs > htmlTime;
  });
  if (stale.length) {
    throw new Error(key + ': published HTML is older than editable source(s): ' + stale.join(', ') +
      '; rebuild, retemplate, check and review before publishing');
  }
}
verifyIndexInventory();
for (const [key] of ACTIVE) requirePair(key);
for (const [key] of ARCHIVE) requirePair(key);
for (const [key] of DRAFTS) {
  if (!existsSync(`${BIZ_ROOT}/tools/${key}.html`)) throw new Error(key + ': draft source missing');
}
for (const [key] of GUIDES) {
  for (const ext of ['html', 'pdf']) {
    if (!existsSync(`${BIZ_ROOT}/${key}.${ext}`)) {
      throw new Error(key + ': published guidance ' + ext + ' missing');
    }
  }
  const html = `${BIZ_ROOT}/${key}.html`;
  const pdf = `${BIZ_ROOT}/${key}.pdf`;
  if (statSync(pdf).mtimeMs < statSync(html).mtimeMs) {
    throw new Error(key + ': guidance PDF is older than its HTML; rerun print and review');
  }
}

const activeRows = ACTIVE.map(([key, title, description, tag]) => {
  const ask = fundingAsk(`${BIZ_ROOT}/${key}/${key}.html`);
  const grant = ask ? `IN-forespørsel NOK ${formatNok(ask)}` : 'ingen IN-forespørsel oppført';
  return `  <li><a href="${key}/${key}.html">${title}</a> — ${description} <span class="tag">${grant} · ${tag}</span></li>`;
}).join(String.fromCharCode(10));
const draftRows = DRAFTS.map(([key, title, description, tag]) => {
  const ask = fundingAsk(`${BIZ_ROOT}/tools/${key}.html`);
  const grant = ask ? `foreløpig IN-forespørsel NOK ${formatNok(ask)}` : 'ingen IN-forespørsel budsjettert';
  return `  <li><a href="tools/${key}.html">${title}</a> — ${description} <span class="tag">${grant} · arbeidsutkast; PDF og visuell kontroll gjenstår · ${tag}</span></li>`;
}).join(String.fromCharCode(10));
const archiveRows = ARCHIVE.map(([key, title]) =>
  `  <li><a href="${key}/${key}.html">${title}</a></li>`).join(String.fromCharCode(10));
const guideRows = GUIDES.map(([path, title, description]) =>
  `  <li><a href="${path}.html">${title}</a> — ${description}</li>`).join(String.fromCharCode(10));
const activeAsk = ACTIVE.reduce((sum, [key]) => sum + fundingAsk(`${BIZ_ROOT}/${key}/${key}.html`), 0);
const draftAsk = DRAFTS.reduce((sum, [key]) => sum + fundingAsk(`${BIZ_ROOT}/tools/${key}.html`), 0);

const html = `<!DOCTYPE html>
<html lang="no">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>biz — aktive planer og arbeidsutkast i pub5-anlegget</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400..800;1,400..800&family=Source+Serif+4:ital,opsz,wght@0,8..60,200..900;1,8..60,200..900&display=swap">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body{background:#fff;color:#000;font:400 1rem/1.5 "Source Serif 4",serif;width:90%;max-width:33rem;margin:auto;text-rendering:optimizeLegibility;letter-spacing:-0.01em}
main{padding:4.5rem 0 3rem;padding-inline:0.75rem}
h1{font:600 2.4rem/1.2 "EB Garamond",serif;margin:0 0 .75rem;hyphens:none;letter-spacing:-0.015em}
p{margin:0 0 .75em;text-wrap:pretty;orphans:3;widows:3;hyphens:auto}
ol{margin:0 0 .75em;padding-left:1.25em}
li{margin:.45em 0;text-wrap:pretty}
a{color:#005f73;text-decoration:underline;text-decoration-thickness:1.5px;text-underline-offset:2px}
a:hover,a:focus-visible{color:#003087}
.tag{font-style:italic;color:#777;font-size:.85em}
h2{font:600 1.3rem/1.3 "EB Garamond",serif;margin:2.5rem 0 .5rem}
footer{margin-top:4.5rem;padding-top:1.5rem;border-top:1px solid #ddd;font-size:.75rem;color:#888}
footer p{margin:0 0 .5em;text-align:left}
</style>
</head>
<body>
<main>
  <h1>Aktive forretningsplaner</h1>
  <p>Fem planer har publiserte HTML/PDF-par. Beløpet summerer bare den eksplisitte Innovasjon Norge-raden i finansieringstabellene: NOK ${formatNok(activeAsk)}. Prosjektkapital, politisk innsamling og bankkapital er ikke blandet inn.</p>
  <ol>
${activeRows}
  </ol>
  <h2>Arbeidsutkast — ikke publisert som PDF</h2>
  <p>To nye konsepter er under arbeid. Foreløpig Innovasjon Norge-forespørsel i utkastene: NOK ${formatNok(draftAsk)}. Beløpene er ikke innsendte søknader, tilsagn eller bekreftet støtteberettigelse.</p>
  <ol>
${draftRows}
  </ol>
  <h2>Søknadsveiledning</h2>
  <p>Praktisk forberedelsesmateriale for et konkret kunstprosjekt. Veiledningen er ikke en innsendt søknad, et vedtak eller en bekreftelse på støtteberettigelse.</p>
  <ol>
${guideRows}
  </ol>
  <h2>Historisk arkiv</h2>
  <p>SPEIS og Fremtidens NATO-våpen er kildene til NORDVAKT. Norwegian Hedge er bevart som et eldre kvantkonsept, ikke som bankens aktive plan.</p>
  <ol>
${archiveRows}
  </ol>
  <footer>
    <p>Satt i Source Serif 4 og EB Garamond via Google Fonts · mål 33 rem · linjeavstand 1,5 · setningscase.</p>
    <p>Kilde: BIZ/tools/bp_index.mjs. Finansieringsbeløp leses fra planenes tabeller · november 2026.</p>
  </footer>
</main>
</body>
</html>`;
writeFileSync(`${BIZ_ROOT}/index.html`, html);
console.log(`index.html written; published IN requests NOK ${formatNok(activeAsk)}; draft requests NOK ${formatNok(draftAsk)}`);
