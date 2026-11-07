# frozen_string_literal: true

# Build BIZ/fetat/fetat.html from BIZ/fetat/proposal.md.
#
# The BIZ business-plan setup (Johann, 2026-11-07: "all business plans follow
# this setup"): a Norwegian proposal.md is the source of truth; this build
# renders it through the bob2 template tokens into one self-contained
# fetat.html, and the PDF is printed from that file so the pair cannot
# drift. The masthead mark on page one is image.jpg → trace.rb → fetat.svg.
#
# Template: BIZ/__templates/bob2.html (Johann, 2026-11-07: "use the bob2.html
# document as template"). bob2's structure, CSS tokens and footer are adopted
# directly; Source Serif 4 for text, EB Garamond for headings, black on white.
# The template keeps its letter form: no generated marks, no frame, Norwegian.
#
# Laws the run through laws.yml enforces on the copy (2026-11-07: "RUN IT
# THROUGH LAWS.YML" - the audit lists every law and its verdict):
#   NO_SPACED_EM_DASH   - the spaced en dash, never an em dash.
#   QUOTES_BY_LOCALE    - «guillemets» in copy, never straight quotes.
#   PARENTHETICAL_DASH  - the spaced en dash, never a plain hyphen.
#   NUMBER_UNIT_UNBROKEN - «48 timer» is one word.
#   TABULAR_NUMERALS    - counts in tabular figures.
#   TYPEFACE_PER_ROLE / BRINGHURST_scale - two serif families, two weights.
#   BRINGHURST_measure  - 42rem standing column (~66 characters).
#   BASELINE_SPACE_MULTIPLES - spacing on the half-lead and whole leads.
#   PRINT_PAGE_CANON    - classical print margins, foot largest.
#   PRINT_FOLIO_PRESENCE - every printed page carries its folio.
#   HEADING_WRAP_BALANCE, WIDOW_ORPHAN_BLOCKED, HANGING_PUNCTUATION,
#   SINGLE_SENTENCE_SPACE, TRUE_SYMBOLS, EMPHASIS_ONE_DEVICE.
#   DENSITY_no_trailing_arrow - the footer link carries no arrow.

require "cgi"

SRC = File.expand_path("fetat_proposal.md", __dir__)
OUT = File.expand_path("../fetat/fetat.html", __dir__)

# Page one is the hands: the retraced mark, filling the whole first page
# with FETAT centered in the footer area of that page.
inline_svg = File.read(File.expand_path("../fetat/fetat.svg", __dir__)).sub(/\A<\?xml.*?\?>\n/, "")

lines = File.readlines(SRC)

def inline(text)
  t = CGI.escapeHTML(text)
  t.gsub!(/`([^`]+)`/) { "<code>#{$1}</code>" }
  t.gsub!(/\*\*([^*]+)\*\*/) { "<strong>#{$1}</strong>" }
  t.gsub!(%r{(?<!\w)\*([^*\n]+)\*(?!\w)}) { "<em>#{$1}</em>" }
  # NUMBER_UNIT_UNBROKEN joins a number and its unit into one word;
  # TABULAR_NUMERALS sets the count itself in tabular figures.
  t.gsub!(/(\d+)\s+(timer|år)\b/) { %(<span class="count">#{$1}</span>&nbsp;#{$2}) }
  t.gsub!(/\[([^\]]+)\]\(([^)\s]+)\)/) do
    label, href = $1, $2
    href.start_with?("http") ? %(<a href="#{CGI.escapeHTML(href)}">#{label}</a>) : label
  end
  t
end

out = String.new
list = nil
table = nil
headings = []

# A list item lives on one line; any new block level closes the open list.
# A blank line ends a table's body but keeps the list open (lists continue
# across blank lines in markdown).
close_list = lambda do
  if list
    tag = list.start_with?("ol") ? "ol" : "ul"
    out << "</#{tag}>\n"
    list = nil
  end
  if table
    out << "</tbody></table>\n"
    table = nil
  end
end

lines.each_with_index do |line, i|
  line = line.chomp

  if line.match?(/\A\#{1,6}\s/)
    close_list.call
    table = nil
    level = line[/\A#+/].length
    body = line.sub(/\A#+\s+/, "").sub(/\s+#+\s*\z/, "").strip
    next if body.empty?
    next if i.zero? # «FETAT» is the raw filename; the template owns the masthead

    headings << [level, inline(body)]
    out << "<h#{level}>#{inline(body)}</h#{level}>\n"
  elsif line.match?(/\A\s*\z/)
    if table
      out << "</tbody></table>\n"
      table = nil
    end
  elsif (m = line.match(/\A\s*\|(.+)\|\s*\z/))
    close_list.call
    row = m[1].split("|").map(&:strip)
    next if row.all? { |c| c.match?(/\A:?-{2,}:?\z/) }

    if table.nil?
      table = :head
      out << "<table><thead><tr>" << row.map { |c| "<th>#{inline(c)}</th>" }.join << "</tr></thead>\n<tbody>\n"
    else
      out << "<tr>" << row.map { |c| "<td>#{inline(c)}</td>" }.join << "</tr>\n"
    end
  elsif (m = line.match(/\A(\s*)([-*]|\d+\.)\s+(.*)\z/))
    table = nil
    depth = m[1].length >= 2 ? 2 : 1
    ordered = m[2].match?(/\d/)
    tag = ordered ? "ol" : "ul"
    if list != "#{tag}#{depth}"
      close_list.call
      out << "<#{tag}>\n"
      list = "#{tag}#{depth}"
    end
    out << "<li>#{inline(m[3])}</li>\n"
  elsif line.match?(/\A---+\s*\z/)
    close_list.call
    table = nil
    out << "<hr>\n"
  else
    table = nil
    unless line.strip.empty?
      close_list.call
      out << "<p>#{inline(line.strip)}</p>\n"
    end
    list = table = nil
  end
end
close_list.call if table
out << "</tbody></table>\n" if table

nav = headings.select { |l, _| l <= 3 }.map do |level, body|
  plain = body.gsub(/<[^>]+>/, "")
  "  #{'  ' * (level - 1)}<p class=\"lv#{level}\">#{plain}</p>"
end.join("\n")

html = <<~HTML
  <!DOCTYPE html>
  <html lang="nb">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta name="description" content="FETAT / Familieetaten – arbeidsmesterdokument">
      <title>FETAT – forretningsplanen for Familieetaten</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,400..800;1,400..800&family=Source+Serif+4:ital,opsz,wght@0,8..60,200..900;1,8..60,200..900&family=Source+Sans+3:ital,wght@0,200..900;1,200..900&display=swap">
      <style>
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
        .cover {
          /* The cover is the page, not a column: full-bleed, pulled out of
             the 33rem measure by negative margins so the hands fill page one. */
          min-height: 94vh;
          width: min(100vw, 200%);
          margin-inline: calc((100% - min(100vw, 200%)) / 2);
          display: flex; flex-direction: column;
          break-after: page; page-break-after: always;
          padding: 0; overflow: hidden;
        }
        .cover svg {
          width: min(112%, 126vh); height: auto;
          margin: auto -6%;
        }
        .cover .mark {
          font: 600 1rem/1.1 "Source Sans 3", sans-serif;
          letter-spacing: 0.42em; text-indent: 0.42em;
          text-align: center; margin: var(--space-m) 0;
        }
        header { margin: 0 auto; }
        /* The cover mark already says FETAT; the semantic h1 stays for the
           document's structure but visually the wordmark stands alone. */
        .vh {
          position: absolute; width: 1px; height: 1px; overflow: hidden;
          clip-path: inset(50%); white-space: nowrap;
        }
        header h1 {
          font: 600 var(--font-size-h1)/var(--line-height-heading) var(--font-heading);
          color: var(--color-text); margin: var(--space-l) auto; text-align: center;
          letter-spacing: -0.015em; text-wrap: balance;
        }
        h2 {
          font: 600 var(--font-size-h2)/var(--line-height-subheading) var(--font-heading);
          margin: var(--space-xl) 0; letter-spacing: -0.01em; text-wrap: balance;
        }
        h1.mark-sub, .toc h2 { font: 600 1.4rem/1.3 var(--font-heading); }
        h3 { font: 600 1.3rem/1.3 var(--font-heading); margin: var(--space-l) 0 var(--space-s); text-wrap: balance; }
        h4 { font: 400 1.05rem/1.3 var(--font-heading); margin: var(--space-m) 0 var(--space-xs); color: var(--color-text); }
        p { margin-bottom: var(--space-l); orphans: 2; widows: 2; }
        strong { font-weight: 600; }
        .count { font-variant-numeric: tabular-nums; }
        .metahead { margin: 0 auto var(--space-l); text-align: center; }
        .metahead p { margin: 0 0 var(--space-s); color: var(--color-muted); }
        .metahead .status { font-style: italic; }
        .metahead .date { font-style: italic; font-feature-settings: "onum" 1; }
        a {
          color: var(--color-link); text-decoration: underline;
          text-decoration-thickness: var(--underline-thickness); text-underline-offset: var(--underline-offset);
        }
        a:focus { outline: 2px solid var(--color-link); outline-offset: 2px; }
        code { font-family: ui-monospace, Menlo, monospace; font-size: 0.88em; }
        ul, ol { margin: 0 0 var(--space-l); padding-left: var(--space-xl); }
        li { margin-bottom: var(--space-list-item); }
        .toc {
          font-size: var(--font-size-small); line-height: 1.6;
          margin: 0 auto var(--space-xxl); padding: var(--space-m) 0;
          break-after: page; page-break-after: always;
        }
        .toc .lv1 { font-family: var(--font-heading); font-weight: 600; margin: var(--space-s) 0 2px; }
        .toc .lv2 { margin: 0 0 1px var(--space-m); color: var(--color-muted); }
        .toc .lv3 { margin: 0 0 1px calc(var(--space-m) * 2); color: var(--color-muted); font-size: var(--font-size-xsmall); }
        .toc p { margin: 0; }
        .toc h2 { margin: 0 0 var(--space-s); }
        footer {
          font-size: var(--font-size-xsmall); color: var(--color-footer-text);
          margin-top: var(--space-xl); padding: var(--space-m) 0;
        }
        footer p { margin: 0; }
        footer a strong { color: var(--color-link-bold); }
        @media (max-width: 768px) {
          :root { --font-size-h1: 2.1rem; --font-size-h2: 1.35rem; }
        }
        @media print {
          /* The printed document is the Chrome render, paged: the screen
             tokens, measure, cover and contents all stand as rendered; the
             @page box adds the hefte size, the folio and break hygiene
             only. Margin boxes sit 18mm/24mm top and foot; the sides are
             held by the body's own centered column. */
          @page {
            size: 156mm 234mm;
            margin: 18mm 0 24mm;
            @bottom-center { content: counter(page); }
          }
          body { margin: 0; }
          p { widows: 2; orphans: 2; }
          h2, h3, h4 { break-after: avoid; }
          h1, .metahead, .signature { page-break-inside: avoid; }
          a[target="_blank"]::after, a[href^="mailto:"]::after { content: none; }
          a:focus { outline: none; }
        }
      </style>
    </head>
    <body>
      <main>
        <section>
          <article>
            <section class="cover">
              #{inline_svg}
              <p class="mark">FETAT</p>
            </section>
            <header>
              <h1 class="vh">FETAT</h1>
              <div class="metahead">
                <p class="status">Arbeidsmesterdokument; grunnlag for regjeringsbehandling og etablering av det statlige organet.</p>
                <p class="date"><time datetime="2026-10-29">29. oktober 2026</time></p>
              </div>
            </header>
            <div class="toc" aria-label="Innhold">
              <h2>Innhold</h2>
              #{nav}
            </div>
            #{out}
            <footer>
              <p><a href="https://fetat.no" target="_blank" aria-label="Besøk Fetat"><strong>www.fetat.no</strong></a> – Rettferdighet for Ola &amp; Kari, med Norges beste AI.</p>
              <p>Opphavsrett © 2026 Fetat, Kanalveien 10, NO-5068 Bergen.</p>
            </footer>
          </article>
        </section>
      </main>
    </body>
  </html>
HTML

File.write(OUT, html)
puts "wrote #{OUT} (#{File.size(OUT)} bytes)"
