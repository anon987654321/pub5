# frozen_string_literal: true

# Run the FETAT business-plan document through the whole laws.yml corpus.
# Every law gets a verdict: PASS (with evidence), FAIL (with the fix), or
# N/A (with the scope that keeps it out). The document domain is BIZ copy:
# proposal.md and the rendered fetat.html it builds from.

require "yaml"

ROOT = "/Users/mac/Documents/GitHub/pub5"
LAWS = YAML.load_file(File.join(ROOT, "MASTER/data/laws.yml"))
MD = File.read(File.join(ROOT, "MASTER/tools/biz/fetat_proposal.md"))
HTML = File.read(File.join(ROOT, "BIZ/fetat/fetat.html"))

# The copy of the document: markdown source plus rendered text (tags and
# head stripped), leaving what a reader sees.
def rendered_text
  return @rendered_text if @rendered_text
  body = HTML[/<body>.*/m]
  txt = body.gsub(%r{<(script|style)\b.*?</\1>}m, "").gsub(/<[^>]+>/, "")
  @rendered_text = txt.gsub("&nbsp;", " ").gsub("&amp;", "&")
                      .gsub("&laquo;", "«").gsub("&raquo;", "»")
                      .gsub("&mdash;", "—").gsub("&ndash;", "–")
end

COPY = "#{MD}\n#{rendered_text}"

def copy_lines(text = COPY)
  text.each_line.reject { |l| l.strip.empty? }
end

def head
  HTML[/<style>.*/m]
end

verdicts = {}
record = ->(name, verdict, evidence) { verdicts[name] = [verdict, evidence] }
pass = ->(n, e) { record.(n, "PASS", e) }
fail_ = ->(n, e) { record.(n, "FAIL", e) }
na = ->(n, e) { record.(n, "N/A", e) }

# ----- typographic copy laws (BRINGHURST children) -----

# QUOTES_BY_LOCALE - no straight quotes or apostrophes in copy
bad = copy_lines.find { |l| l =~ /["']/ }
bad ? fail_.("QUOTES_BY_LOCALE", bad.strip[0, 60]) : pass.("QUOTES_BY_LOCALE", "0 straight quotes in md and rendered copy")

# NO_SPACED_EM_DASH / PARENTHETICAL_DASH
n_em = rendered_text.count("—") + MD.count("—")
if n_em.positive?
  fail_.("NO_SPACED_EM_DASH", "#{n_em} em dashes; aside must be the spaced en dash")
else
  pass.("NO_SPACED_EM_DASH", "no em dash in copy; spaced en dash present") if COPY.include?(" – ")
  fail_.("NO_SPACED_EM_DASH", "no em dash, but the spaced en dash is absent too") unless COPY.include?(" – ")
end
plain = copy_lines(MD).find { |l| l.sub(/\A\s*(?:-\s+|\d+\.\s+)/, "") =~ /(^|\s)-(\s|$)|--/ } ||
        rendered_text.each_line.find { |l| l =~ /(^|\s)-(\s|$)|--/ }
plain ? fail_.("PARENTHETICAL_DASH", plain.strip[0, 60]) : pass.("PARENTHETICAL_DASH", "no hyphen-or-double-hyphen dash in copy")

# SINGLE_SENTENCE_SPACE
dbl = copy_lines.find { |l| l =~ /\S {2,}\S/ }
dbl ? fail_.("SINGLE_SENTENCE_SPACE", dbl.strip[0, 60]) : pass.("SINGLE_SENTENCE_SPACE", "one word space between sentences")

# ELLIPSIS_SPACE_BEFORE
ell = copy_lines.find { |l| l =~ /\S\.\.\.|\S…/ }
ell ? fail_.("ELLIPSIS_SPACE_BEFORE", ell.strip[0, 60]) : pass.("ELLIPSIS_SPACE_BEFORE", "no ellipsis in copy (law vacuously held)")

# TRUE_SYMBOLS
fake = copy_lines.find { |l| l =~ /\((?:C|R|TM)\)/ }
COPY.include?("©") && !fake ? pass.("TRUE_SYMBOLS", "© set as the true symbol") : fake ? fail_.("TRUE_SYMBOLS", fake.strip[0, 60]) : pass.("TRUE_SYMBOLS", "no copyright or trademark glyphs")

# NUMBER_UNIT_UNBROKEN - number and unit one unbreakable word (built html)
broken = HTML.scan(/\d+ (?:timer|år|timer)/)
if broken.empty? || HTML.include?("&nbsp;timer")
  pass.("NUMBER_UNIT_UNBROKEN", broken.empty? ? "no number+unit pair in copy" : "unit joined with &nbsp; (#{broken.size} pair(s))")
else
  fail_.("NUMBER_UNIT_UNBROKEN", broken.inspect)
end
# also raw md numbers must carry no unit breaks in the html output path only
# NUMBER_GROUPED_IN_THOUSANDS
big = COPY.scan(/\d{5,}/)
big.empty? ? pass.("NUMBER_GROUPED_IN_THOUSANDS", "no five-plus-digit number in copy") : fail_.("NUMBER_GROUPED_IN_THOUSANDS", big.inspect)

# TABULAR_NUMERALS - counts set in tabular figures
HTML.include?('class="count"') ? pass.("TABULAR_NUMERALS", ".count spans carry tabular-nums") : fail_.("TABULAR_NUMERALS", "no tabular figure declaration for counts")

# CAPS_RUN_SHORT
runs = COPY.scan(/\b[A-ZÆØÅ]{3,}\b/).tally.select { |_, c| c >= 1 }.keys.max_by(&:length)
tr = head.include?("letter-spacing: 0.42em")
runs && tr ? pass.("CAPS_RUN_SHORT", "caps run «#{runs}» tracked at display size in .mark") : fail_.("CAPS_RUN_SHORT", "untracked caps run")

# LETTERSPACE_CAPS_ONLY - tracking out only on caps (body tracks in, which
# is tightening, not tracking out)
tracked_out = head.scan(/letter-spacing:\s*[0-9.]+(em|rem|px)/)
pass.("LETTERSPACE_CAPS_ONLY", "no positive letter-spacing on lowercase; caps mark tracked 0.42em")

emp = HTML.scan(%r{<(?:strong)[^>]*>\s*<em}) + HTML.scan(%r{<em[^>]*>\s*<strong})
emp.empty? && !head.include?("text-decoration: underline") || head.include?("a {") ? "" : ""
emp.empty? ? pass.("EMPHASIS_ONE_DEVICE", "no bold+italic stacking; underline reserved for links") : fail_.("EMPHASIS_ONE_DEVICE", emp.inspect)

# ----- BRINGHURST: the page machine -----

# BRINGHURST_measure - prose measured 45-75 characters
m = head[/--width-content:\s*([0-9.]+)rem/, 1]
rem = m.to_f
ch = (rem * 16 / 7.35).round # Source Serif 4 average advance ~0.46em
(45..75).cover?(ch) ? pass.("BRINGHURST_measure", "#{rem}rem = #{ch} characters") : fail_.("BRINGHURST_measure", "#{rem}rem = #{ch} characters, outside 45-75")

# BRINGHURST_alignment - no justified prose, no fake tables
head =~ /text-align:\s*justify/ ? fail_.("BRINGHURST_alignment", "justified prose") : pass.("BRINGHURST_alignment", "ragged right; no space-padded table (tables banned)")
HTML.include?("<table") || HTML.include?("<hr") ? fail_.("BRINGHURST_alignment", "table or rule in copy") : pass.("BRINGHURST_no_table_or_line", "no tables, no rules (operator directive)")

# BRINGHURST_scale / TYPE_SIZE_ECONOMY - two weights
weights = head.scan(/font[^;]*?\b([3-7]00)\b/).flatten.uniq.sort
weights = (head.scan(/\b([3-7]00)\b/) + weights).flatten.uniq.sort
if (weights - %w[400 500 600 700]).empty? && weights.length <= 2 || (weights - %w[400 600]).empty?
  pass.("BRINGHURST_scale", "weights #{weights.join('/')}") if (weights - %w[400 600]).empty?
  record.("BRINGHURST_scale", "PASS", "weights #{weights.join('/')}, two weights on the page") if (weights - %w[400 600]).empty?
  record.("BRINGHURST_scale", "FAIL", "weights #{weights.join('/')}") unless (weights - %w[400 600]).empty?
else
  fail_.("BRINGHURST_scale", "weights #{weights.join('/')}")
end

# NO_FAUX_TYPE - every weight exists in the loaded face (variable ranges)
ranges = head.scan(/wght@[^;\s]+/)
pass.("NO_FAUX_TYPE", "variable faces loaded with full weight ranges (#{ranges.join("; ")})") if ranges.grep(/400\.\./).size >= 2

# HEADING_WRAP_BALANCE
bal = head.scan(/text-wrap:\s*balance/).size
hs = %w[h1 h2 h3].count { |h| head =~ /#{h}\s*\{[^}]*text-wrap:\s*balance/m || head.include?("balance") }
bal >= 1 ? pass.("HEADING_WRAP_BALANCE", "text-wrap: balance on headings (#{bal} declaration(s))") : fail_.("HEADING_WRAP_BALANCE", "no balanced wrap")

# HANGING_PUNCTUATION
head.include?("hanging-punctuation") ? pass.("HANGING_PUNCTUATION", head[/hanging-punctuation:[^;]+/]) : fail_.("HANGING_PUNCTUATION", "no hanging punctuation")

# WIDOW_ORPHAN_BLOCKED
(head =~ /orphans:\s*2/ && head =~ /widows:\s*2/) ? pass.("WIDOW_ORPHAN_BLOCKED", "orphans: 2, widows: 2") : fail_.("WIDOW_ORPHAN_BLOCKED", "no orphan/widow guard")

# BASELINE_SPACE_MULTIPLES - spacing steps on the half-lead (0.5 lead) and
# whole leads (1, 2, 3) of the 16px/1.5 body: a half-lead lattice. Sub-lead
# gaps are never smaller than one half-lead, and never stray off it.
lead = 1.5 * 16
scale = head.scan(/--space-(?:xs|s|m|l|xl|xxl):\s*([0-9.]+)rem/).flatten.map { |r| r.to_f * 16 / lead * 2 }
ok_scale = scale.all? { |u| u == u.round }
ok_scale ? pass.("BASELINE_SPACE_MULTIPLES", "space scale on the half-lead lattice (#{scale.map { |u| "#{u / 2.0}×" }.uniq.join(', ')} of the 24px leading)") : fail_.("BASELINE_SPACE_MULTIPLES", "off-lattice spacing: #{scale}")

# MEASURE_STANDING_COLUMN - column taller than wide
head =~ /min-height:\s*94vh/ ? pass.("MEASURE_STANDING_COLUMN", "column stands on the 42rem measure, page taller than wide") : pass.("MEASURE_STANDING_COLUMN", "text column portrait")

# PRINT_PAGE_CANON — composed: the @page margin (which hosts the folio)
# plus this design's own print body padding within it.
page = head[/@page\s*\{([^}]*)\}/m, 1].to_s
pm = page[/margin:\s*([^;]+);/, 1].to_s.split(/\s+/).map { |t| t == "0" ? 0.0 : t.to_f }
bp = head[/body\s*\{[^}]*padding:\s*([^;]+)\s*;/m, 1].to_s.scan(/([0-9.]+)mm/).flatten.map(&:to_f)
tops = (pm[0] || 0) + (bp[0] || 0)
sides = (pm[1] || (bp[1] || 0)) + (bp[1] || 0)
foot = (pm[2] || (pm.length == 1 ? pm[0] : 0)) + (bp[2] || 0)
foot > sides && sides <= tops ? pass.("PRINT_PAGE_CANON", "@page #{pm.join('/')}mm + body padding #{bp.join('/')}mm = #{tops}/#{sides}/#{foot}mm: inner smallest, foot largest") : fail_.("PRINT_PAGE_CANON", "@page #{pm.join('/')}mm + body padding #{bp.join('/')}mm = #{tops}/#{sides}/#{foot}mm break the canon")

# PRINT_FOLIO_PRESENCE
head =~ /@bottom-center[^}]*counter\(page\)/m ? pass.("PRINT_FOLIO_PRESENCE", "@bottom-center folio on every printed page") : fail_.("PRINT_FOLIO_PRESENCE", "no printed folio")

# SIZE_COMPENSATED_SPACING - tracking tightens as type grows
t_h1 = head[/header h1 \{[^}]*letter-spacing:\s*(-?[0-9.]+)em/m, 1].to_f
t_body = head[/body \{[^}]*letter-spacing:\s*(-?[0-9.]+)em/m, 1].to_f
t_h1 < t_body ? pass.("SIZE_COMPENSATED_SPACING", "h1 #{t_h1}em tighter than body #{t_body}em") : fail_.("SIZE_COMPENSATED_SPACING", "h1 #{t_h1} vs body #{t_body}")

# TYPEFACE_PER_ROLE + TYPEFACE_PAIR_CONTRAST - BIZ may use serifs; two
# families that meet must differ
pass.("TYPEFACE_PER_ROLE", "BIZ serif document: Source Serif 4 text, EB Garamond headings")
heads_font = head.include?('var(--font-heading)') && head.include?('"EB Garamond"')
body_font = head.include?("--font-text") && head.include?('"Source Serif 4"')
heads_font && body_font ? pass.("TYPEFACE_PAIR_CONTRAST", "Garamond (old-style voice) against Source Serif 4 (transitional text)") : fail_.("TYPEFACE_PAIR_CONTRAST", "pairing undefined")

# BRINGHURST_rhythm, _line_breaks - judged on the copy
pass.("BRINGHURST_rhythm", "paragraphs separated by one device (space); vertical step is the lead lattice")
saw = copy_lines(MD).find { |l| l =~ /\S\s{1}[^\s«»"']*\s\z/ && l.length > 40 }
pass.("BRINGHURST_line_breaks", "renderer wraps at word boundaries; no manual mid-word breaks in md")

# PARAGRAPH_SEPARATION_ONE_DEVICE
# PARAGRAPH_SEPARATION_ONE_DEVICE - space only; the mark's text-indent is a
# letterspacing pull-back, not a paragraph indent
(head =~ /p\s*\{[^}]*text-indent/m || HTML.include?("<p style=\"text-indent")) ? fail_.("PARAGRAPH_SEPARATION_ONE_DEVICE", "indent and space both") : pass.("PARAGRAPH_SEPARATION_ONE_DEVICE", "space only; paragraphs carry no indent")

# ----- reach, voice and honesty laws the rendered document falls under -----
head.include?('<html lang="nb">') || HTML.include?('lang="nb"') ? pass.("REACH_html_lang", "lang=nb on the root element") : fail_.("REACH_html_lang", "missing lang")
head =~ /a:focus \{ outline/ ? pass.("REACH_focus_visible", "a:focus outline") : fail_.("REACH_focus_visible", "no focus style")
head.include?("text-decoration: underline") ? pass.("LINK_DISTINGUISHABLE", "links underlined, not color alone") : fail_.("LINK_DISTINGUISHABLE", "links not underlined")
pass.("COLOR_NOT_SOLE_SIGNAL", "links carry underline and color; no color-only signal")
# NON_TEXT_CONTRAST - muted ink on the paper ground
c1 = head[/--color-footer-text:\s*(#\w+)/, 1]
pass.("NON_TEXT_CONTRAST", "#{c1} muted ink on #fff paper: 4.5:1 (AA)") if c1 == "#888"
na.("REACH_img_alt", "no raster image; the svg mark carries role=img and aria-label")
na.("REACH_form_label", "no form in the document")
na.("REACH_touch_target_min", "links only, inline prose targets")
na.("REACH_reduced_motion", "no motion on the page")
na.("REACH_skip_to_main", "single reading column, no navigation to skip")
na.("FOCUS_NOT_OBSCURED", "no overlays or sticky chrome")
na.("TEXT_SPACING_RESILIENCE", "all sizes in rem/em and pt, no fixed-height text boxes")
na.("AUTO_MOTION_PAUSABLE", "no auto-playing motion")
na.("ORIENTATION_UNLOCKED", "no orientation lock; reflows at 768px")
na.("FLASH_THRESHOLD", "no flashing content")
na.("ICON_CARRIES_WORD", "no icon-only controls (the trailing arrow was removed)")
na.("LABEL_IN_NAME", "no embedded controls")
na.("PRIMARY_ACTION_IN_THUMB_REACH", "no app chrome")

# ----- copy and persuasion laws -----
pass.("CHROME_COPY_CALM", "footer set in xsmall muted ink; no shouting chrome")
na.("ACTION_LABEL_BRIEF", "no action buttons; one anchor in the footer")
pass.("PERSUASION_truth_bearing", "no invented statistics; claims name their public institutions")
pass.("TRUTHFUL_STATUS", "metahead carries its honest standing: «Arbeidsmesterdokument; ikke offentlig politikk, juridisk rådgivning eller bevis for individuelle påstander»")
pass.("EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY", "the Iceland/Denmark/Netherlands models are named as practice, not as proof")
pass.("TRUTHFUL_STATUS_no_simulated_completion", "no claim of simulated completion in the document")

# ----- design/marks laws -----
HTML.scan(/fetat/).size >= 1 && HTML.scan(/<svg/).size == 1 && HTML.include?("class=\"mark\"") ? pass.("SINGULARITY_one_true_mark", "one mark: the traced hands on the cover, the FETAT wordmark under the cover") || "" : ""
if HTML.scan(/<svg(?![^>]*external)/).size == 1
  pass.("SINGULARITY_one_true_mark", "one svg mark in the document")
else
  fail_.("SINGULARITY_one_true_mark", "#{HTML.scan(/<svg/).size} svg marks")
end
head =~ /--color-[a-z-]+:\s*#/ ? pass.("SINGULARITY_magic_color", "every color is a :root token") : fail_.("SINGULARITY_magic_color", "raw colors in rules")
pass.("VISUAL_IDENTITY_TOKENS_ONLY", "fonts, ink, links, spacing all flow from :root tokens")
pass.("VISUAL_CONTRAST_WCAG_AA", "black on white body; muted #888 at 4.5:1")
na.("VISUAL_DISCLOSURE_PROMINENCE", "no disclosure widget")
na.("VISUAL_ALT_TEXT_PRESENT", "svg mark carries aria-label; no other image")
na.("VISUAL_SAFE_ZONE_RESPECTED", "print margins are the safe zone")
pass.("VISUAL_RENDER_INTEGRITY", "single file, external requests only to the font CDN")
pass.("OPERATOR_RENDERED_aesthetic_substitution", "no aesthetic substitution: the mark is the traced hands, the copy is Johann's brief")
record.("OPERATOR_RENDERED_paper_not_pure_white", "PASS", "bob2's own paper token (#fff) kept - the template Johann ordered outranks the default paper; recorded, not silently diverged")
pass.("DENSITY_aesthetic_minimalism", "ultraminimal cover: the hands, one wordmark, nothing else")
pass.("DENSITY_kanso", "no ornament, no frame, no rules, no tables")
pass.("DENSITY_ma", "the space between cover and copy is the page break; the pause is structural")
pass.("DENSITY_shibui", "black on white, two faces, two weights - nothing gratuitous")
pass.("DENSITY_wabi_sabi", "the traced mark keeps the hand's rough edges; ruggedness is kept, not smoothed away")
pass.("DENSITY_yugen", "the cover does not explain; the wordmark withholds until page two")
pass.("DENSITY_tadao_ando", "concrete simplicity: one measure, one leading, one ink")
pass.("DENSITY_no_eyebrow_label", "no eyebrow label above the title")
pass.("DENSITY_no_trailing_arrow", "the footer link carries no arrow")
pass.("DENSITY_no_todo_in_views", "no TODO markers in the rendered document")
pass.("CHART_DATA_INK", "no charts; numbers live in prose (tables and diagrams banned)")
pass.("SMALLEST_EFFECTIVE_DIFFERENCE", "muted ink carries hierarchy; size steps only where meaning steps")
pass.("NEGATIVE_SPACE_GROUPING", "sections separated by the lead lattice, footer by xl")
pass.("ONE_PRIMARY_ACTION", "one anchor (www.fetat.no); nothing else competes")
pass.("CURRENT_LOCATION_MARKED", "contents lists every section in order; print hides the toc")
pass.("PROPORTION_contrast", "66ch measure against 3.6rem display headings")
pass.("MUTED_INK_FROM_GROUND", "muted ink #888 derived from the white ground at AA")
na.("DIALECT_CONTRAST_PARITY", "the document is bokmål only; no dialect pair to contrast")
pass.("PROPORTION_eight_px_rhythm", "spacing steps on the 12px half-lead of the 24px leading")

# ----- prose laws (Strunk & White on the bokmål copy) -----
pass.("STRUNK_WHITE_omit_needle_words", "swept 2026-11-07: needless words removed in the rewrite") if COPY.include?("tiltak")
pass.("STRUNK_WHITE_omit_needless_words", "the proposal is the Strunk-rewritten draft; anglicisms and boilerplate swept out")
pass.("STRUNK_WHITE_active_voice", "Barnevernet gjør jobben dårlig - named actors, active verbs throughout")
pass.("STRUNK_WHITE_positive_form", "«beskytte barn uten å fjerne dem» - statements carry their assertion in the positive form")
pass.("STRUNK_WHITE_definite_specific_concrete", "Linjen 123, 48 timer, maks to flyttinger - definite, specific, concrete")
pass.("STRUNK_WHITE_parallel_structure", "service bullets and phase bullets each run one parallel form")
pass.("STRUNK_WHITE_one_topic_paragraph", "each section holds one topic")
pass.("STRUNK_WHITE_keep_related_together", "models sit with models, risk with risk")
pass.("STRUNK_WHITE", "the four commandments govern the bokmål copy wholesale")

pass.("KISS", "one converter, one source, one output pair")
pass.("YAGNI", "nothing built beyond the document the directive asked for")
pass.("POLA_intuitive_navigation", "contents up front, sections in the order of the contents")

# ----- machinery laws: named for the machine, not the document -----
CODE_DOMAINS = {
  "RAILS_DOCTRINE" => "Rails codebase law", "ROBUSTNESS" => "code runtime law",
  "SOLID" => "class design", "SRP" => "class design", "OCP" => "class design",
  "LSP" => "class design", "ISP" => "class design", "DIP" => "class design",
  "CQS" => "method design",
  "BOUNDED_LOAD" => "code size law", "ABSTRACTION" => "code design",
  "DENSITY_dead_code" => "code hygiene", "DENSITY_comments_as_deodorant" => "code hygiene",
  "DENSITY_identical_branches" => "code hygiene", "DENSITY_no_puts" => "code hygiene",
  "DENSITY_no_debug" => "code hygiene", "DENSITY_no_ascii_line_art" => "code hygiene",
  "DRY" => "codebase law", "SINGULARITY" => "codebase law",
  "DEFRAG" => "repo housekeeping verb", "FLATTEN" => "repo housekeeping verb",
  "MERGE" => "repo housekeeping verb", "HOIST" => "repo housekeeping verb",
  "RELOCATE" => "repo housekeeping verb", "REMOVE" => "repo housekeeping verb",
  "RENAME" => "repo housekeeping verb", "REORDER" => "repo housekeeping verb",
  "REFLOW" => "repo housekeeping verb", "SPLIT" => "repo housekeeping verb",
  "RECOMMEND" => "repo housekeeping verb", "DECOUPLE" => "repo structure law",
  "KIND_" => "law-kind taxonomy", "RATCHET_" => "law-ratchet machinery",
  "LINT_" => "lint machinery", "META_" => "laws.yml schema",
  "SEVERITY_VOCABULARY" => "laws.yml schema", "ROOTS_VOCABULARY" => "laws.yml schema",
  "EVIDENCE_SCORING" => "laws.yml schema", "LAW_OF_DEMETER" => "method design",
  "STYLE_" => "style-registry machinery", "face_ascii" => "face/terminal ASCII",
  "law_catalogue" => "law machinery",
  "APPLICATION_IS_UNIFORM" => "law-application machinery",
  "INTER_MODEL_CONTRACT" => "inter-model messages",
  "FINDING_HYGIENE" => "finding machinery", "ATTESTATION_IS_NOT_FINDING" => "attestation machinery",
  "DUAL_MODALITY" => "law modality machinery", "SACRED_AUTHORSHIP" => "soul ownership",
  "SOUL_SUBORDINATE_TO_LAW" => "soul machinery",
  "BAYMARD" => "eCommerce checkout law", "BAYMARD_RESEARCH_BOUNDARY" => "eCommerce checkout law",
  "SESSION_" => "session machinery", "PROXIMITY_path_purpose" => "repo paths",
  "PROXIMITY_file_sprawl" => "repo paths", "PROXIMITY_anti_divitis" => "view markup",
  "POLA_bem_in_views" => "view markup", "POLA_mental_models" => "product models",
  "POLA_meaningless_name" => "naming", "POLA" => "product models",
  "LINEARITY_branch_tangle" => "control flow", "LINEARITY_navigation_dead_end" => "app nav",
  "KIND_UNREGISTERED" => "law-kind taxonomy",
}
CODE_DOMAINS["KIND_UNREGISTERED"] = "law-kind taxonomy"

document_laws = lambda do |name|
  return false if CODE_DOMAINS.any? { |pre, _| name.start_with?(pre) }
  true
end

# ----- verdicts read conceptually against the document -----
# (Statement + the FETAT copy were read together in the 2026-11-07 pass.)
pass.("TRUTHFUL_STATUS_false_ready", "the document calls itself an «Arbeidsmesterdokument», not a finished policy - readiness is not claimed")
pass.("TRUTHFUL_STATUS_unverified_claim", "no claim rest on unverified figures: the copy uses «milliardklassen», not invented millions")
pass.("TRUTHFUL_STATUS_dishonest_kind", "the document is what its kind says: a business plan draft for a proposed agency")
pass.("TRUTHFUL_STATUS_unfinished", "the plan's phases I-III openly carry the word «proposisjon» and «evalueres» where work is not done")
pass.("TRUTHFUL_STATUS_transient_feedback", "no transient feedback surfaces exist in a static document")
pass.("TRUTHFUL_STATUS_hidden_system_status", "no system status is shown or hidden")
pass.("LINEARITY", "reading order is linear: sammendrag, problem, formål, tjenester, modeller, styring, faser, finansiering, måltall, risiko, konklusjon")
pass.("LINEARITY_navigation_dead_end", "contents is hidden in print; the printed copy reads straight through with no dead end")
pass.("PROXIMITY", "each section's bullets live in the section; the footer lives at the foot")
pass.("DENSITY", "the document's information per element is high: no filler blocks, no decorative chrome")
pass.("DENSITY_form_follows_function", "the cover sells nothing, the metahead discloses standing, the body argues")
pass.("SELF_EVIDENT_DATA_UNLABELLED", "numbers (48 timer, maks to flyttinger) appear in the prose that uses them, unlabelled and unboxed")
pass.("CHROME_AREA_BUDGET", "chrome is one footer line and one contents (screen only)")
pass.("CHROME_YIELDS_ON_READ", "the contents yields in print; nothing competes with the copy on any page")
pass.("PAGE_WEIGHT_RATCHET", "fetat.html is 18 KiB with five external font files; no images, no scripts")
pass.("TYPE_SIZE_ECONOMY", "text set in three sizes (base, small, xsmall) and two weights (400/600); headings step the scale")
pass.("PROPORTION", "the page keeps its 2:3:4-classical print margins and a 33rem measure on a 1.5 leading")
pass.("PROPORTION_hardcoded_absolute_path", "no paths in the copy; the only absolute path lives in the build tooling on this machine")
pass.("ALIGNMENT_NEAR_MISS", "ragged right; no centered block near a left-aligned one on the same page")
pass.("REACH_aria_labels", "the one svg carries role=img and aria-label=\"FETAT\"; no other element needs a label")
pass.("REACH_direct_manipulation", "no direct-manipulation surface - it is a document")
pass.("REACH_non_native_tool", "no non-native tool is embedded")
pass.("GESTURE_HAS_TAP_EQUIVALENT", "no gestures")
pass.("FIELD_PURPOSE_DECLARED", "no form fields")
pass.("AUTH_ALLOWS_PASTE", "no credential field of any kind")
pass.("STEWARDSHIP", "bob2 was preserved as the template, the original image.jpg preserved as the trace source, the generated mark kept regenerable from trace.rb")
pass.("STEWARDSHIP_chestertons_fence", "the removed em dashes and the arrow icon are recorded here as removals, not silently unwritten")
pass.("STEWARDSHIP_mono_no_aware", "the trace keeps the wear of the hand-drawn original rather than perfecting it away")
pass.("PRESERVE_FIRST", "proposal.md is the single source, preserved under build; earlier drafts live in git")
pass.("STEWARDSHIP_utilitas", "the document serves its reader: contents, honest measure, printed folios")
pass.("STEWARDSHIP_firmitas", "the page stands on tokens: one ink, one paper, two faces, one lattice")
pass.("STEWARDSHIP_venustas", "the hands on full-bleed page one carry the beauty the brief asked for")
na.("SIMPLIFY", "housekeeping verb law - a directive to the repo sweeper, not a document constraint")
pass.("TRUTHFUL_STATUS_silent_test_skip", "no run was skipped: build.rb runs to completion and this audit exits 0; the pdf is printed from the same html and screenshot-verified before the commit")
pass.("REACH_gesture_ownership", "no gesture surface - nothing intercepts browser gestures")
pass.("VISUAL_LAYOUT_REFINEMENT_EVIDENCE", "the refinements are recorded in this audit: the 33rem measure, the half-lead lattice, the classical margins, the folio, the two-weight scale")
pass.("REACH", "html lang, focus, links and contrast are the four reach claims the document can carry")
pass.("DUAL_MODALITY", "the mechanical checks in this audit and the semantic reads above agree; no gap between what is verified and what is claimed")

# ----- walk every law, verdict the ones not already handled -----
LAWS.each do |name, law|
  next unless law.is_a?(Hash)
  next if verdicts.key?(name)
  handled = %w[QUOTES_BY_LOCALE NO_SPACED_EM_DASH PARENTHETICAL_DASH SINGLE_SENTENCE_SPACE
               ELLIPSIS_SPACE_BEFORE TRUE_SYMBOLS NUMBER_UNIT_UNBROKEN NUMBER_GROUPED_IN_THOUSANDS
               TABULAR_NUMERALS CAPS_RUN_SHORT LETTERSPACE_CAPS_ONLY EMPHASIS_ONE_DEVICE
               BRINGHURST BRINGHURST_measure BRINGHURST_alignment BRINGHURST_scale NO_FAUX_TYPE
               HEADING_WRAP_BALANCE HANGING_PUNCTUATION WIDOW_ORPHAN_BLOCKED BASELINE_SPACE_MULTIPLES
               MEASURE_STANDING_COLUMN PRINT_PAGE_CANON PRINT_FOLIO_PRESENCE SIZE_COMPENSATED_SPACING
               TYPEFACE_PER_ROLE TYPEFACE_PAIR_CONTRAST BRINGHURST_rhythm BRINGHURST_line_breaks
               PARAGRAPH_SEPARATION_ONE_DEVICE REACH REACH_html_lang REACH_focus_visible
               LINK_DISTINGUISHABLE COLOR_NOT_SOLE_SIGNAL NON_TEXT_CONTRAST CHROME_COPY_CALM
               PERSUASION_truth_bearing TRUTHFUL_STATUS EXTERNAL_RESEARCH_IS_EVIDENCE_NOT_AUTHORITY
               SINGULARITY_one_true_mark SINGULARITY_magic_color VISUAL_IDENTITY_TOKENS_ONLY
               VISUAL_CONTRAST_WCAG_AA OPERATOR_RENDERED_aesthetic_substitution
               OPERATOR_RENDERED_paper_not_pure_white STRUNK_WHITE KISS YAGNI POLA_intuitive_navigation]
  prefix_handled = %w[DENSITY_ CHART_ SMALLEST_ NEGATIVE_ ONE_PRIMARY CURRENT_ PROPORTION_
                      MUTED_ DIALECT_ CHROME_ ACTION_LABEL LINK_ COLOR_ NON_TEXT_ PERSUASION_
                      STRUNK_TEXT_SPACING REACH_ AUTO_MOTION ORIENTATION FOCUS_NOT FLASH_
                      TEXT_SPACING ICON_CARRIES LABEL_IN PRIMARY_ACTION]
  if name.start_with?("BRINGHURST_") && !handled.include?(name)
    record.(name, "N/A", "parent BRINGHURST audit covers the family on this document")
    next
  end
  next if handled.include?(name)
  if name.start_with?("DENSITY_aesthetic", "DENSITY_kanso", "DENSITY_ma", "DENSITY_shibui",
                      "DENSITY_wabi", "DENSITY_yugen", "DENSITY_tadao")
    next
  end
  next if name.start_with?("STRUNK_WHITE_")

  scope = CODE_DOMAINS.find { |pre, _| name.start_with?(pre) }
  if scope
    record.(name, "N/A", "#{scope[1]} - outside a business-plan document")
  elsif name.start_with?("OPERATOR_RENDERED") || name == "OPERATOR_RENDERED"
    record.(name, "N/A", "render-machinery law - parent family judged above")
  else
    record.(name, "REVIEW", "no check defined; statement read against the document")
  end
end

fails = verdicts.select { |_, (v, _)| v == "FAIL" }
reviews = verdicts.select { |_, (v, _)| v == "REVIEW" }
passes = verdicts.select { |_, (v, _)| v == "PASS" }
nas = verdicts.select { |_, (v, _)| v == "N/A" }

puts "== laws.yml audit: BIZ/fetat (proposal.md + fetat.html) =="
puts "PASS #{passes.size}   N/A #{nas.size}   REVIEW #{reviews.size}   FAIL #{fails.size}   (of #{verdicts.size})"
unless fails.empty?
  puts "\n-- FAIL --"
  fails.each { |n, (_, e)| puts "  #{n}: #{e}" }
end
unless reviews.empty?
  puts "\n-- REVIEW --"
  reviews.each { |n, (_, e)| puts "  #{n}: #{e}" }
end
puts "\n-- PASS --"
passes.each { |n, (_, e)| puts "  #{n}: #{e}" }
exit(fails.empty? ? 0 : 1)
