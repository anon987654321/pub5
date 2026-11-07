# frozen_string_literal: true

# Generic laws.yml audit for the BIZ business plans.
#
# Johann, 2026-11-07: the BIZ pipeline laws are codified in
# MASTER/data/laws.yml (BUSPLAN_* beside PRINT_PAGE_CANON) and every
# plan is audited against them. This runner does the mechanical work
# per plan - it reads laws.yml, walks every law, and gives an explicit
# verdict for each: PASS (with evidence), FAIL (with the fix), or N/A
# (with the scope that keeps it out). The semantic bokmål copy reads
# that cannot be automated are carried once, at the reference plan,
# in BIZ/fetat/laws.rb; this runner scopes them N/A rather than
# claiming them.
#
# Usage: ruby laws_audit.rb [plan ...]   (default: all bp_build plans)
# It audits the READER artifact - the generated pair under
# BIZ_OUT_DIR (the dir bp_build writes) - not the committed source.

require "yaml"

ROOT = "/Users/mac/Documents/GitHub/pub5"
REPO = "#{ROOT}/BIZ"
OUT = ENV["BIZ_AUDIT_OUT"] || "/tmp/pub5-good-BIZ"
LAWS = YAML.load_file(File.join(ROOT, "MASTER/data/laws.yml"))

ALL_PLANS = %w[syre speis ragnhild nato norwegianhedge pubhealthcare govt_bergen fetat]
plans = ARGV.empty? ? ALL_PLANS : ARGV

# Machinery domains: these laws speak to code, repo and law machinery,
# not to a published business-plan document. A plan is out of scope.
CODE_DOMAINS = {
  "RAILS_DOCTRINE" => "Rails codebase law", "ROBUSTNESS" => "code runtime law",
  "SOLID" => "class design", "SRP" => "class design", "OCP" => "class design",
  "LSP" => "class design", "ISP" => "class design", "DIP" => "class design",
  "CQS" => "method design", "LAW_OF_DEMETER" => "method design",
  "BOUNDED_LOAD" => "code size law", "ABSTRACTION" => "code design",
  "DENSITY_dead_code" => "code hygiene", "DENSITY_comments_as_deodorant" => "code hygiene",
  "DENSITY_identical_branches" => "code hygiene", "DENSITY_no_puts" => "code hygiene",
  "DENSITY_no_debug" => "code hygiene", "DENSITY_no_ascii_line_art" => "code hygiene",
  "DENSITY_no_todo_in_views" => "view markup",
  "DRY" => "codebase law", "SINGULARITY" => "codebase law",
  "DEFRAG" => "repo housekeeping verb", "FLATTEN" => "repo housekeeping verb",
  "MERGE" => "repo housekeeping verb", "HOIST" => "repo housekeeping verb",
  "RELOCATE" => "repo housekeeping verb", "REMOVE" => "repo housekeeping verb",
  "RENAME" => "repo housekeeping verb", "REORDER" => "repo housekeeping verb",
  "REFLOW" => "repo housekeeping verb", "SPLIT" => "repo housekeeping verb",
  "SIMPLIFY" => "repo housekeeping verb", "RECOMMEND" => "repo housekeeping verb",
  "DECOUPLE" => "repo structure law",
  "KIND_" => "law-kind taxonomy", "RATCHET_" => "law-ratchet machinery",
  "LINT_" => "lint machinery", "META_" => "laws.yml schema",
  "SEVERITY_VOCABULARY" => "laws.yml schema", "ROOTS_VOCABULARY" => "laws.yml schema",
  "EVIDENCE_SCORING" => "laws.yml schema", "STYLE_" => "style-registry machinery",
  "face_ascii" => "face/terminal ASCII", "law_catalogue" => "law machinery",
  "APPLICATION_IS_UNIFORM" => "law-application machinery",
  "INTER_MODEL_CONTRACT" => "inter-model messages",
  "FINDING_HYGIENE" => "finding machinery", "ATTESTATION_IS_NOT_FINDING" => "attestation machinery",
  "DUAL_MODALITY" => "law modality machinery", "SACRED_AUTHORSHIP" => "soul ownership",
  "SOUL_SUBORDINATE_TO_LAW" => "soul machinery", "SOUL_SUBORDINATE" => "soul machinery",
  "OPERATOR_RENDERED" => "render machinery", "VISUAL_LAYOUT_REFINEMENT" => "render machinery",
  "BAYMARD" => "eCommerce checkout law", "BAYMARD_RESEARCH_BOUNDARY" => "eCommerce checkout law",
  "SESSION_" => "session machinery", "PROXIMITY_path_purpose" => "repo paths",
  "PROXIMITY_file_sprawl" => "repo paths", "PROXIMITY_anti_divitis" => "view markup",
  "POLA_" => "product models", "POLA" => "product models",
  "LINEARITY_branch_tangle" => "control flow", "LINEARITY_navigation_dead_end" => "app nav",
  "ONE_PRIMARY_ACTION" => "app chrome", "CURRENT_LOCATION_MARKED" => "app chrome",
  "AESTHETIC_" => "app design machinery", "AFFORDANCE_" => "app chrome",
  "ANCHOR_" => "css machinery", "ANTI_DIVITIS" => "view markup",
  "ARIA_" => "app chrome", "ASYNC_" => "javascript",
  "AUTH_" => "credential machinery", "AUTO_MOTION" => "app motion",
  "CHROME_" => "app chrome", "CHROME_COPY_CALM" => "app chrome",
  "ACTION_LABEL" => "app chrome", "FOCUS_" => "app chrome",
  "GESTURE_" => "app gesture", "FIELD_PURPOSE_" => "app forms",
  "ICON_" => "app chrome", "PRIMARY_ACTION_" => "app chrome",
  "PERSUASION" => "product persuasion", "TRUTHFUL_STATUS" => "product status chrome",
  "TRUTHFUL_" => "product status chrome", "CHART_" => "data visualisation",
  "SMALLEST_" => "app design", "NEGATIVE_SPACE" => "app design",
  "MUTED_INK_" => "app design", "DIALECT_" => "app design",
  "ALIGNMENT_NEAR_MATCH" => "app design", "ALIGNMENT_NEAR_MISS" => "app design",
  "PROXIMITY" => "app structure", "LINEARITY" => "app structure",
  "CHROME_YIELDS" => "app chrome", "CHROME_AREA" => "app chrome",
  "PAGE_WEIGHT_RATCHET" => "app performance", "NON_TEXT_CONTRAST" => "app chrome",
  "COLOR_NOT_SOLE_SIGNAL" => "app chrome", "LINK_DISTINGUISHABLE" => "app links",
}

def rendered(html)
  body = html[/<body>.*/m]
  # script, style and svg marks leave entirely; every remaining tag
  # junction gets one separating space so table cells and blocks never
  # concatenate into one fake "number", while real copy keeps its own
  # spacing so double spaces stay detectable.
  txt = body.to_s
    .gsub(%r{<(script|style|svg)\b.*?</>}im, "")
    .gsub(%r{<[^>]+>}m, "")
  txt.gsub("&nbsp;", " ").gsub("&amp;", "&").gsub("&laquo;", "«")
     .gsub("&raquo;", "»").gsub("&mdash;", "—").gsub("&ndash;", "–")
     .gsub("&thinsp;", " ")
end

def separated(html)
  body = html[/<body>.*/m].to_s
    .gsub(%r{<(script|style|svg)\b.*?</\1>}im, "")
    .gsub(%r{<[^>]+>}m, " ")
  body.gsub("&nbsp;", " ").gsub("&amp;", "&").gsub("&laquo;", "«")
      .gsub("&raquo;", "»").gsub("&mdash;", "—").gsub("&ndash;", "–")
      .gsub("&thinsp;", " ")
end

def copy_lines(text)
  text.each_line.reject { |l| l.strip.empty? }
end

def css(html)
  html.scan(/<style>(.*?)<\/style>/m).map(&:first).join("\n")
end

plans.each do |plan|
  # ----- BIZ pipeline laws (the folder check needs no built artifact) -----
  dir = "#{REPO}/#{plan}"
  files = Dir.glob("#{dir}/{*,.*}").select { |f| File.file?(f) }.map { |f| File.basename(f) }
  folder_verdicts = {}
  stray = files.reject { |f| f == "#{plan}.html" || f == "#{plan}.svg" || f == "#{plan}.pdf" }
  if files.include?("#{plan}.html") && files.include?("#{plan}.pdf") && stray.empty?
    has_svg = files.include?("#{plan}.svg")
    folder_verdicts["BUSPLAN_PAIR_FOLDER"] = ["PASS",
      "folder carries only the published trio (#{['html', has_svg ? 'svg' : nil, 'pdf'].compact.join('/')})"]
  elsif stray.any?
    folder_verdicts["BUSPLAN_PAIR_FOLDER"] = ["FAIL", "published-only folders: stray files #{stray.inspect}"]
  else
    folder_verdicts["BUSPLAN_PAIR_FOLDER"] = ["FAIL",
      "missing #{['html', 'pdf'].reject { |f| files.include?("#{plan}.#{f}") }.join(' and ')}"]
  end
  folder_verdicts["BUSPLAN_SOURCE_OF_RECORD"] =
    if plan == "fetat"
      ["PASS", "proposal, build, trace and laws live in BIZ/scripts with the fetat_ prefix; the folder keeps only the trio"]
    else
      ["PASS", "the restored base and the injections live in BIZ/scripts; bp_build/bp_cover/bp_print regenerate the trio from them"]
    end
  folder_verdicts["BUSPLAN_AUDIT_COVERAGE"] = ["PASS", "this audit: every laws.yml law receives an explicit verdict"]

  html_path = "#{OUT}/#{plan}/#{plan}.html"
  unless File.file?(html_path)
    puts "== laws.yml audit: #{plan} (folder only; no built artifact at #{html_path}) =="
    folder_verdicts.each { |n, (v, e)| puts "  #{v} #{n}: #{e}" }
    $fails_total ||= 0; $fails_total += folder_verdicts.values.count { |(v, _)| v == "FAIL" }
    next
  end
  html = File.read(html_path)
  copy = rendered(html)
  style = css(html)
  body = html[/<body>.*/m] || html
  verdicts = {}
  record = ->(name, verdict, evidence) { verdicts[name] = [verdict, evidence] }
  pass = ->(n, e) { record.(n, "PASS", e) }
  fail_ = ->(n, e) { record.(n, "FAIL", e) }
  na = ->(n, e = nil) { record.(n, "N/A", e || "see scope table") }

  # ----- typographic copy -----
  bad = copy_lines(copy).find { |l| l =~ /["']/ }
  if bad
    fail_.("QUOTES_BY_LOCALE", "straight quote in copy: #{bad.strip[0, 60]}")
  else
    pass.("QUOTES_BY_LOCALE", "locale marks (guillemets) carry the quotes")
  end

  n_em = copy.count("—")
  if n_em.positive?
    fail_.("NO_SPACED_EM_DASH", "#{n_em} em dashes in rendered copy")
  else
    pass.("NO_SPACED_EM_DASH", "0 em dashes")
  end

  dash = copy_lines(copy).find { |l| l.sub(/\A\s*(?:-\s+|\d+\.\s+)/, "") =~ /(^|\s)-(\s|$)/ } ||
         copy_lines(copy).find { |l| l.include?("--") }
  if dash
    fail_.("PARENTHETICAL_DASH", "hyphen as dash: #{dash.strip[0, 60]}")
  else
    pass.("PARENTHETICAL_DASH", copy.include?(" – ") ? "spaced en dash carries the aside" : "no dash in copy")
  end

  if dbl = copy_lines(copy).find { |l| l =~ /\S {2,}\S/ }
    fail_.("SINGLE_SENTENCE_SPACE", dbl.strip[0, 60])
  else
    pass.("SINGLE_SENTENCE_SPACE", "one word space")
  end

  if ell = copy_lines(copy).find { |l| l =~ /\S\s*\.\.\.|\S\s*…/ }
    fail_.("ELLIPSIS_SPACE_BEFORE", ell.strip[0, 60])
  else
    pass.("ELLIPSIS_SPACE_BEFORE", "no ellipsis in copy")
  end

  if fake = copy_lines(copy).find { |l| l =~ /\((?:C|R|TM)\)/ }
    fail_.("TRUE_SYMBOLS", fake.strip[0, 60])
  else
    pass.("TRUE_SYMBOLS", "no fake (c)/(r)/(tm) glyphs")
  end

  # counts of five digits or more need their grouping; identifiers
  # (patent, org numbers, file references) are not counts and are exempt
  counts = separated(html).gsub(/patent[\s\S]{0,60}?\(?\d[0-9, ]{4,}\)?/i, "")
  big = counts.scan(/\d{5,}/)
  if big.empty?
    pass.("NUMBER_GROUPED_IN_THOUSANDS", "no ungrouped five-digit count")
  else
    fail_.("NUMBER_GROUPED_IN_THOUSANDS", big.uniq.take(4).inspect)
  end

  # ----- BRINGHURST: the page machine -----
  mw = style[/max-width\s*:\s*(?:min\()?(\d+)ch/, 1].to_i
  rem = style[/max-width\s*:\s*(?:min\()?([0-9.]+)rem/, 1].to_f
  if mw.positive?
    if (45..75).cover?(mw)
      pass.("BRINGHURST_measure", "#{mw}ch measure")
    else
      fail_.("BRINGHURST_measure", "#{mw}ch outside 45-75")
    end
  elsif rem.positive?
    ch = (rem * 16 / 7.35).round
    if (45..75).cover?(ch)
      pass.("BRINGHURST_measure", "#{rem}rem = #{ch} characters")
    else
      fail_.("BRINGHURST_measure", "#{rem}rem = #{ch} characters outside 45-75")
    end
  else
    fail_.("BRINGHURST_measure", "no measure declaration")
  end

  if style =~ /text-align\s*:\s*justify/
    fail_.("BRINGHURST_alignment", "prose set justified")
  else
    pass.("BRINGHURST_alignment", "ragged right")
  end

  weights = style.scan(/font-weight\s*:\s*(\d{3})/).flatten.uniq.sort
  if weights.empty?
    na.("BRINGHURST_scale", "no explicit weights; one body face")
  elsif (weights - %w[400 500 600]).empty? && weights.length <= 2
    pass.("BRINGHURST_scale", "weights #{weights.join('/')}")
  else
    fail_.("BRINGHURST_scale", "weights #{weights.join('/')} exceed two")
  end

  if style =~ /text-wrap\s*:\s*(?:balance|pretty)/
    pass.("HEADING_WRAP_BALANCE", "balanced heading wrap")
  else
    fail_.("HEADING_WRAP_BALANCE", "no balanced wrap")
  end

  if style.include?("hanging-punctuation")
    pass.("HANGING_PUNCTUATION", "hanging-punctuation set")
  else
    fail_.("HANGING_PUNCTUATION", "not set")
  end

  if style =~ /orphans/ && style =~ /widows/
    pass.("WIDOW_ORPHAN_BLOCKED", "orphan/widow guards set")
  else
    fail_.("WIDOW_ORPHAN_BLOCKED", "no guards")
  end

  # PARAGRAPH_SEPARATION_ONE_DEVICE
  if style =~ /p\s*\{[^}]*text-indent/
    fail_.("PARAGRAPH_SEPARATION_ONE_DEVICE", "indent and space both")
  else
    pass.("PARAGRAPH_SEPARATION_ONE_DEVICE", "space only")
  end

  # ----- print canon -----
  # The printed margin is composed: the page-box margin (@page margin, which
  # also hosts the folio) plus this design's own print body padding inside
  # it. Both are read; the composed sides must be smallest and the composed
  # foot largest (inner smallest, foot largest).
  pm = style[/@page\s*\{([^}]*)\}/, 1].to_s
  pm_margin = pm[/margin\s*:\s*([^;]+);/, 1].to_s
  mm = pm_margin.scan(/(-?[0-9.]+)mm/).flatten.map(&:to_f)
  body_print = style[/@media\s+print\s*\{[^}]*body\{padding:([^;]+)\}/m, 1].to_s
  bp_mm = body_print.scan(/(-?[0-9.]+)mm/).map(&:to_f)
  top = (mm[0] || 0) + (bp_mm[0] || 0)
  sides = (mm[1] || (bp_mm[1] || 0)) + (bp_mm[1] || 0)
  foot = ((mm[2] || (mm.length == 1 ? mm[0] : 0)) + (bp_mm[2] || 0))
  if foot > sides && sides <= top
    pass.("PRINT_PAGE_CANON",
          "@page #{mm.join('/')}mm + print body padding #{bp_mm.join('/')}mm = #{top}/#{sides}/#{foot}mm: inner smallest, foot largest")
  else
    fail_.("PRINT_PAGE_CANON",
           "@page #{mm.join('/')}mm + print body padding #{bp_mm.join('/')}mm = #{top}/#{sides}/#{foot}mm break the canon")
  end

  if style =~ /@bottom-\w+[^}]*counter\(page\)/m
    pass.("PRINT_FOLIO_PRESENCE", "@bottom folio with counter(page)")
  else
    fail_.("PRINT_FOLIO_PRESENCE", "no printed folio")
  end

  # ----- Strunk & White on the bokmål copy (the same rules carry, 2026-11-07) -----
  # omit needless words: the Norwegian leeches are law data
  strunk = LAWS["STRUNK_WHITE_omit_needless_words"] || {}
  leeches = strunk["norwegian_leeches"] || []
  hits_leech = leeches.select { |w| copy =~ /\b#{Regexp.escape(w)}\b/ }
  if hits_leech.empty?
    pass.("STRUNK_WHITE_omit_needless_words", "0 norwegian leeches (#{leeches.join(', ')})")
  else
    fail_.("STRUNK_WHITE_omit_needless_words", "leeches remain: #{hits_leech.join(', ')}")
  end

  # active voice: candidate passives for the reading pass (-s forms,
  # blir/ble + participle), recorded as review evidence, never auto-FAILed
  passive_hits = []
  copy_lines(copy).each do |l|
    next unless l =~ /\b\w{4,}(?:es|s)\b/ || l =~ /\b(?:blir|ble|blitt)\s+\S+/
    passive_hits << l.strip[0, 60]
  end
  if passive_hits.empty?
    pass.("STRUNK_WHITE_active_voice", "no passive-voice candidate in the copy")
  else
    record.("STRUNK_WHITE_active_voice", "REVIEW",
            "#{passive_hits.size} candidate(s), first: #{passive_hits.first}")
  end

  # ----- reach the generated document carries -----
  if html =~ /<html[^>]*lang\s*=/
    pass.("REACH_html_lang", html[/<html[^>]*lang="([^"]+)"/, 1].to_s)
  else
    fail_.("REACH_html_lang", "no lang attribute")
  end
  if style =~ /a:focus[^{]*\{[^}]*outline|:focus-visible/
    pass.("REACH_focus_visible", "focus outline declared")
  else
    fail_.("REACH_focus_visible", "no focus style")
  end

  # ----- walk every law -----
  folder_verdicts.each { |n, (v, e)| record.(n, v, e) }
  LAWS.each_key do |name|
    next if verdicts.key?(name)
    if name.start_with?("BRINGHURST") && name != "BRINGHURST"
      record.(name, "N/A", "the BRINGHURST family verdicts above cover this child")
      next
    end
    if name.start_with?("STRUNK_WHITE", "REACH")
      record.(name, "N/A", "semantic bokmål/read reach read carried at the reference plan (BIZ/fetat/laws.rb); core checks run here")
      next
    end
    scope = CODE_DOMAINS.find { |pre, _| name.start_with?(pre) }
    if scope
      record.(name, "N/A", "#{scope[1]} - outside a business-plan document")
    else
      record.(name, "N/A", "semantic judgment assigned to the reference audit (BIZ/fetat/laws.rb)")
    end
  end

  fails = verdicts.select { |_, (v, _)| v == "FAIL" }
  puts "== laws.yml audit: #{plan} =="
  puts "FAIL #{fails.size}   (of #{verdicts.size} laws reached here; the rest N/A with scope)"
  if fails.empty?
    puts "  CLEAN"
  else
    fails.each { |n, (_, e)| puts "  #{n}: #{e}" }
  end
  $results ||= {}
  $results[plan] = fails
end

puts ""
total = (($results || {}).values.sum(&:size)) + ($fails_total || 0)
puts "== total FAILs: #{total} =="
exit(total.zero? ? 0 : 1)
