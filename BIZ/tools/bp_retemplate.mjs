// Re-skin the eight completed BIZ plans onto the bob2 starter template.
// Johann, 2026-11-07: "all business plans must use bob2.html as starter
// template". bob2's token vocabulary (--color-*, --font-text/--font-heading
// = Source Serif 4 body + EB Garamond headings, spaces, underline metrics)
// is the starter; the plan canon is that vocabulary with the one hefte
// print contract the fetat pages already carry (156mm 234mm, folio in the
// 12mm foot, 6mm head, first page margin-free so the cover is the page,
// break hygiene). Content is extracted from the built plans untouched:
// same header mark, same h1 and byline, same sections, tables and figures,
// same colophon - only the skin changes, and the colophon's first line
// names the new facts (BUSPLAN_COLOPHON_TRUTH).
//
// Usage: node bp_retemplate.mjs   (after bp_build.mjs, before bp_print.mjs)
import { readFileSync, writeFileSync } from 'node:fs';
import { OUTPUT_DIR as OUT } from './paths.mjs';

const ORDER = ['syre', 'speis', 'ragnhild', 'future_nato_weapons', 'norwegianhedge',
  'pubhealthcare', 'govt_bergen', 'future_healthcare_os'];

// The two 8 November 2026 plans were authored straight into the final bob2
// skin (no <nav> to re-extract): the skin is verified, never re-applied.
const COMPLETED = new Set(['future_nato_weapons', 'future_healthcare_os']);

// ---- the plan canon: bob2 tokens + the hefte print contract -----------------
const CANON = `
* { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --color-text: #000; --color-muted: #777; --color-link: #005f73; --color-link-bold: #003087;
  --color-print-muted: #aaa; --color-border: #ddd; --color-icon: #000; --color-background: #fff;
  --color-footer-text: #888; --font-size-base: 1rem; --font-size-small: 0.9rem;
  --font-size-xsmall: 0.75rem; --font-size-h1: 3.6rem; --font-size-h2: 1.8rem;
  --line-height-normal: 1.5; --line-height-heading: 1.2;
  --line-height-subheading: 1.4; --space-xs: 0.75rem; --space-s: 0.75rem; --space-m: 0.75rem;
  --space-l: 1.5rem; --space-xl: 3rem; --space-xxl: 4.5rem; --space-list-item: 0;
  --width-content: 33rem; --width-indent: 16.2px; --layout-margin: auto;
  --font-text: "Source Serif 4", serif; --font-heading: "EB Garamond", serif;
  --underline-thickness: 1.5px; --underline-offset: 2px;
}
html { font-size: 16px; }
body {
  font: 400 var(--font-size-base)/var(--line-height-normal) var(--font-text);
  color: var(--color-text); background: var(--color-background);
  width: 90%; max-width: var(--width-content); margin: var(--layout-margin);
  text-rendering: optimizeLegibility; letter-spacing: -0.01em;
}
main { padding-inline: var(--space-m); }
article { margin-bottom: var(--space-xxl); hanging-punctuation: first last; }
/* The cover is the page, not a column: the plan mark, the title pushed to
   the foot of the page and the byline carry page one as on fetat. */
header.cover {
  min-height: 94vh; display: flex; flex-direction: column;
  text-align: center; padding: var(--space-xl) 0;
  break-after: page; page-break-after: always;
}
.cover .mark, .cover .mark-brand { margin: 0 auto; }
.cover h1 {
  font: 600 2.6rem/1.2 var(--font-heading);
  margin: auto 0; letter-spacing: -0.015em; text-wrap: balance;
}
.cover .byline { font-style: italic; color: var(--color-muted); margin: var(--space-m) 0; }
h2 {
  font: 600 var(--font-size-h2)/var(--line-height-subheading) var(--font-heading);
  margin: var(--space-xl) 0; letter-spacing: -0.01em; text-wrap: balance;
}
h3 { font: 600 1.3rem/1.3 var(--font-heading); margin: var(--space-l) 0 var(--space-s); text-wrap: balance; }
h4 { font: 400 1.05rem/1.3 var(--font-heading); margin: var(--space-m) 0 var(--space-xs); color: var(--color-text); }
p { margin-bottom: var(--space-l); orphans: 2; widows: 2; }
strong { font-weight: 600; }
.count { font-variant-numeric: tabular-nums; }
a {
  color: var(--color-link); text-decoration: underline;
  text-decoration-thickness: var(--underline-thickness); text-underline-offset: var(--underline-offset);
}
a:focus { outline: 2px solid var(--color-link); outline-offset: 2px; }
code { font-family: ui-monospace, Menlo, monospace; font-size: 0.88em; }
ul { margin: 0 0 var(--space-l); padding-left: 1.1em; }
li { margin-bottom: var(--space-list-item); text-wrap: pretty; }
li::marker { color: var(--color-muted); }
dl { margin: 0 0 var(--space-l); }
dt { font-weight: 600; margin-top: 0.6em; }
dd { margin: 0 0 0.35em; padding-left: 1.1em; text-wrap: pretty; }
/* Tables and figures: the archive rules, retokenised onto bob2's colors. */
table { width: 100%; border-collapse: collapse; margin: var(--space-l) 0; font-size: 0.9em; font-variant-numeric: tabular-nums lining-nums; }
caption { caption-side: top; text-align: left; font-style: italic; color: var(--color-muted); font-size: 0.8em; padding-bottom: 0.5rem; }
th, td { padding: 0.3rem 0.6rem 0.3rem 0; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: baseline; hyphens: auto; }
thead th { border-top: 2px solid var(--color-text); border-bottom: 1px solid var(--color-text); font-weight: 600; }
tfoot td { border-top: 1px solid var(--color-text); border-bottom: 2px solid var(--color-text); font-weight: 600; }
table.numbers td, table.numbers th { text-align: right; }
table.numbers td:first-child, table.numbers th:first-child { text-align: left; }
figure { margin: var(--space-xl) 0; }
figure svg { display: block; width: 100%; height: auto; }
figcaption { font-size: 0.8em; font-style: italic; color: var(--color-muted); margin-top: 0.5rem; }
.mark-plain { font-weight: 400; font-size: 1.3em; letter-spacing: 0.05em; line-height: 1.2; }
/* The brand wordmark carries its own display font (ragnhild's Nosifer);
   the rule is the base's, ported so the plan's own mark reads as itself. */
.mark-brand {
  font-family: 'Nosifer', 'EB Garamond', Georgia, serif;
  font-weight: 400; font-size: 2.1em; line-height: 1.45; margin: 0 auto; color: inherit;
}
.mark-brand:empty { display: none; }
.toc {
  font-size: var(--font-size-small); line-height: 1.6;
  margin: 0 auto var(--space-xxl); padding: var(--space-m) 0;
  break-after: page; page-break-after: always;
}
.toc .lv1 { font-family: var(--font-heading); font-weight: 600; margin: var(--space-s) 0 2px; }
.toc p { margin: 0; }
.toc h2 { font: 600 1.4rem/1.3 var(--font-heading); margin: 0 0 var(--space-s); }
footer {
  font-size: var(--font-size-xsmall); color: var(--color-footer-text);
  margin-top: var(--space-xl); padding: var(--space-m) 0;
}
footer p { margin: 0 0 var(--space-s); }
footer a { color: var(--color-footer-text); }
footer a strong { color: var(--color-link-bold); }
@media (max-width: 768px) {
  :root { --font-size-h1: 2.1rem; --font-size-h2: 1.35rem; }
}
@media print {
  /* The printed document is the Chrome render, paged, exactly as fetat:
     the @page box adds the hefte size, the folio and break hygiene only.
     A zero top margin on the first page makes the cover the page. */
  @page {
    size: 156mm 234mm;
    margin: 6mm 0 12mm;
    @bottom-center { content: counter(page); font: 0.75rem/1.4 var(--font-heading); color: var(--color-print-muted); }
  }
  @page :first { margin-top: 0; }
  /* body keeps its auto margins in print: the browser centres the 33rem
     column on the page box, and the pdf must be laid out by the same
     algorithm - pinning body margin to 0 shifted every printed page to
     the left edge and broke the html/pdf twin. */
  header.cover { min-height: 221mm; }
  h2, h3, h4 { break-after: avoid; }
  table, li, figure { break-inside: avoid; }
  h1 { page-break-inside: avoid; }
  footer { page-break-before: always; }
  a { color: inherit; text-decoration: none; }
  a[target="_blank"]::after, a[href^="mailto:"]::after { content: none; }
  a:focus { outline: none; }
}
`;

// The typography colophon must name the facts of this skin (the archive
// line names EB Garamond innbakt and papir #F7F2E9 - both gone).
const COLOPHON_OLD = /^<p>Satt i EB Garamond [^]*?<\/p>$/m;
const COLOPHON_NEW = '<p>Satt i Source Serif 4 (brødtekst) og EB Garamond (titler) · mål 66 tegn · '
  + 'linjeavstand 1,5 · tabelltall i tabeller · titler i setningscase uten versaler – '
  + 'etter Robert Bringhurst, The Elements of Typographic Style.</p>';

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function markStandalonePrintStyle(html, plan) {
  const lines = html.split('\n');
  const index = lines.findIndex(line => /<style\b/i.test(line));
  if (index < 0) throw new Error(plan + ': standalone print stylesheet missing');
  if (!/scan:\s*intentional\b/.test(lines[index])) {
    const indent = lines[index].match(/^\s*/)[0];
    lines[index] = indent + '<!-- scan: intentional - standalone print stylesheet has no asset pipeline -->' + lines[index].slice(indent.length);
  }
  return lines.join('\n');
}

for (const plan of ORDER) {
  const output = `${OUT}/${plan}/${plan}.html`;
  const original = readFileSync(output, 'utf8');
  const src = markStandalonePrintStyle(original, plan);
  if (src !== original) writeFileSync(output, src);
  if (COMPLETED.has(plan)) {
    if (!/class="toc" aria-label="Innhold"/.test(src)) throw new Error(`${plan}: completed base lacks the toc`);
    if (!/Satt i Source Serif 4/.test(src)) throw new Error(`${plan}: completed base lacks the bob2 colophon`);
    if (!/@bottom-center \{ content: counter\(page\)/.test(src)) throw new Error(`${plan}: completed base lacks the folio`);
    console.log(`${plan}: completed base already in the bob2 skin; passed through`);
    continue;
  }
  const bodyStart = src.indexOf('<body>');
  if (bodyStart < 0) throw new Error(`${plan}: no <body>`);

  const title = (src.match(/<title>([^<]+)<\/title>/) || [])[1];
  if (!title) throw new Error(`${plan}: no <title>`);

  const grab = (tag) => {
    const m = src.slice(bodyStart).match(new RegExp(`<${tag}[^>]*>[^]*?</${tag}>`));
    if (!m) throw new Error(`${plan}: no <${tag}>`);
    return m[0];
  };

  // Header, nav-toc, content and footer are extracted untouched.
  const headerRaw = grab('header').replace(/^<header[^>]*>/, '').replace(/<\/header>$/, '');
  const header = headerRaw.trim();
  const navRaw = grab('nav');
  const tocItems = [...navRaw.matchAll(/<li[^>]*>\s*(?:<a[^>]*>([^<]+)<\/a>|([^<]+))\s*<\/li>/g)]
    .map(m => `<p class="lv1">${escapeHtml(m[1] || m[2]).trim()}</p>`)
    .join('\n');
  if (!tocItems.includes('lv1')) throw new Error(`${plan}: nav yielded no toc rows`);
  const footerRaw = grab('footer');
  const footer = footerRaw.replace(COLOPHON_OLD, COLOPHON_NEW);
  if (!footer.includes('Source Serif 4')) throw new Error(`${plan}: colophon not rewritten`);

  const body = src.slice(bodyStart);
  const navEnd = body.indexOf('</nav>') + '</nav>'.length;
  const footerStart = body.indexOf('<footer>');
  const content = body.slice(navEnd, footerStart).trim();
  if (content.length < 15000) throw new Error(`${plan}: content implausibly short (${content.length})`);
  if (!content.includes('<section')) throw new Error(`${plan}: content has no sections`);

  // @font-face rules the content depends on (the brand marks, e.g. Nosifer).
  // EB Garamond comes from the Google Fonts link, as on fetat.
  const faces = [...(src.slice(0, bodyStart).matchAll(/@font-face{[^}]*}/g) || [])]
    .map(m => m[0])
    .filter(f => !/font-family:\s*'EB Garamond'/.test(f))
    .map(f => f.replace(/font-display:swap;/g, ''))
    .join('\n');

  const html = `<!DOCTYPE html>
<html lang="nb">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400..800;1,400..800&family=Source+Serif+4:ital,opsz,wght@0,8..60,200..900;1,8..60,200..900&display=swap">
    <style>
${faces ? '\n' + faces + '\n' : ''}${CANON}
    </style>
  </head>
  <body>
    <main>
      <article>
        <header class="cover">
${header}
        </header>
        <div class="toc" aria-label="Innhold">
          <h2>Innhold</h2>
${tocItems}
        </div>
${content}
${footer}
      </article>
    </main>
  </body>
</html>
`;

  writeFileSync(output, markStandalonePrintStyle(html, plan));
  console.log(`${plan}: rebob2 (${html.length} chars, toc ${tocItems.split('\n').length}, faces ${faces ? faces.split('@font-face').length - 1 : 0})`);
}
