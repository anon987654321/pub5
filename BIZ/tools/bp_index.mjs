// Generate BIZ/index.html: the reader's entry to the plan tree. Sits on the
// bob2 generation (both faces from the Google Fonts link, white ground,
// sentence-case titles) and lists one row per published plan folder, the
// pair funding summed, and the archive members (fetat, ai3) named as what
// they are. The funding total is checked against the folder table, so a
// plan added without its ask fails the run.
// Usage: node BIZ/tools/bp_index.mjs
import { existsSync } from 'node:fs';
import { writeFileSync } from 'node:fs';
import { BIZ_ROOT } from './paths.mjs';

const PLANS = [
  ['syre', 'SYRE™', '3D-printede sko, NOK 250 000', 'Environment & Sustainability'],
  ['ragnhild', 'Ragnhild', 'begravelsesbyrå med Karaokekiste og Diskokiste, NOK 150 000', 'Social Innovation'],
  ['speis', 'SPEIS', 'maritime og forsvar, NOK 500 000', 'Maritime + Defense'],
  ['future_nato_weapons', 'Fremtidens NATO-våpen', 'arktiske dominanseskip og polar SAR-konstellasjon, NOK 500 000', 'Maritime + Defense + Space'],
  ['norwegianhedge', 'Norwegian Hedge', 'Ruby-drevet bot-swarm og AI³, NOK 300 000', 'Technology + Finance'],
  ['pubhealthcare', 'pub.healthcare', 'autonome parametriske sykehus, NOK 500 000', 'Health'],
  ['govt_bergen', 'Bergen Selvstyreparti', 'blockchain-basert lokalt styresett, NOK 200 000', 'Civic Tech'],
  ['future_healthcare_os', 'Fremtidens helse-OS', 'OpenBSD-disiplin, Rails/Rhoda-konvensjoner og MASTERs lovmaskin i helsevesenet, NOK 500 000', 'Health + Infrastructure'],
];
const total = PLANS.reduce((s, p) => s + parseInt(p[2].split('NOK ')[1].replaceAll(' ', ''), 10), 0);
if (total !== 2900000) throw new Error(`funding total ${total} ≠ 2900000`);
// Every linked document must have its published HTML/PDF pair. The archive
// members are linked too, so they are checked rather than silently allowed
// to become dead links.
const PUBLISHED_DOCUMENTS = [...PLANS.map(([key]) => key), 'fetat', 'ai3'];
for (const key of PUBLISHED_DOCUMENTS) {
  for (const extension of ['html', 'pdf']) {
    if (!existsSync(`${BIZ_ROOT}/${key}/${key}.${extension}`)) {
      throw new Error(`${key}: published ${extension} missing from the folder tree`);
    }
  }
}

const rows = PLANS.map(([k, t, d, s]) =>
  `  <li><a href="${k}/${k}.html">${t}</a> — ${d} <span class="tag">${s}</span></li>`).join('\n');

const html = `<!DOCTYPE html>
<html lang="no">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>biz — åtte forretningsplaner i pub5-anlegget</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400..800;1,400..800&family=Source+Serif+4:ital,opsz,wght@0,8..60,200..900;1,8..60,200..900&display=swap">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body{
  background:#fff;color:#000;
  font: 400 1rem/1.5 "Source Serif 4", serif;
  width: 90%; max-width: 33rem; margin: auto;
  text-rendering:optimizeLegibility; letter-spacing:-0.01em;
}
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
  <h1>Åtte forretningsplaner</h1>
  <p>Gjenopprettet fra pub-, pub2- og pub3-arkivene og fullført til
  Innovasjon Norges vurderingskriterier. Søkt finansiering til sammen:
  NOK 2 900 000. Hvert konsept er ett selvbærende HTML-dokument og én PDF
  trykket av det samme dokumentet, i én mappe per plan.</p>
  <ol>
${rows}
  </ol>
  <h2>Arkivmedlemmer</h2>
  <p><a href="fetat/fetat.html">FETAT</a> — Familieetaten, bygd direkte fra
  sitt forslagsnotat etter bob2-oppsettet. <a href="ai3/ai3.html">AI³</a> —
  bevart fra pub3- og pub4-arkivene, ikke i behold-listen for denne
  gjenopprettingen. Malhistorien (bob, bob2, bob3) ligger i
  <span class="tag">__templates/</span>, kildearkene i
  <span class="tag">research/</span>.</p>
  <footer>
    <p>Satt i Source Serif 4 og EB Garamond via Google Fonts-lenken ·
    mål 33 rem · linjeavstand 1,5 · titler i setningscase uten versaler –
    etter Robert Bringhurst, The Elements of Typographic Style. EB Garamond
    og Source Serif 4 utgis under SIL Open Font License.</p>
    <p>Kilde: pub5.good/BIZ · vedlikeholdes av BIZ/tools/bp_index.mjs ·
    november 2026.</p>
  </footer>
</main>
</body>
</html>
`;

writeFileSync(`${BIZ_ROOT}/index.html`, html);
console.log(`index.html written, ${html.length} chars, funding total ${total}`);
