# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: db9a64ede48e4d51
require_relative "../lib/master"

# law/css.rb — every css law, one Law.define per law.
# REDUCED_MOTION and NO_IMPORTANT live once, in the registry (web_laws.rb).
# Both judge a FILE's posture — whether the reset block exists, whether an
# !important erases or paints, whether it sits inside an override media —
# and the per-line twins here fired on face.css's own reduced-motion reset,
# twenty-six findings against a file already doing the right thing.

















# MAGIC_COLOR lives once, in the registry (js_laws.rb): its narrowing —
# token definitions, intentional markers, the mailer and manifest carve-outs —
# is behavioural, measured across 596 retired findings, and a bare hex detector
# beside it double-counted every one it got wrong.


































# One language per layer: a query language inside Ruby, markup inside
# JavaScript, a heredoc smuggling a third grammar past the reader.
#
# Templates are exempt, and have to be. A template is two languages on purpose —
# that is the entire definition — so matching the ERB opening tag flagged the
# thing that makes the file work. Across RAILS' 428 views this rule produced
# 6,826 findings, 75% of everything MASTER reported about those files, and every
# one of them said "this template contains a template". The law/ header calls
# that the decorator-massacre failure mode: a rule whose false-positive rate
# makes the report unreadable stops being enforcement and becomes noise.
#
# The genuine html case — an inline script or style block, five files in the
# whole tree — is NO_INLINE_SCRIPT_BLOCK, where the detector can be honest about
# what it wants instead of catching a language marker by accident.
# The registry twin retired 2026-08-21: its non-erb branch duplicated this
# detector and its erb branch duplicated NO_INLINE_SCRIPT_BLOCK. The bare
# `SQL|HEREDOC` word-match retired with it — it fired on every heredoc
# closing delimiter and on prose that mentioned SQL; only an opening heredoc
# tag smuggles a grammar in.




































# Every Layout (Bell & Pickering): let the content size the box. A fixed pixel
# height on a container is a promise about content the container cannot keep —
# text wraps, translations run long (Norwegian does), and the box clips or
# spills. min-height states the same floor without the ceiling. Below 100px
# the element is a control or a media frame sizing itself, not a text
# container, so the law starts where flowing content starts.
#
# The book's other axiom — space between siblings belongs to the parent (gap),
# not the children (margin-bottom chains) — is not per-line decidable: whether
# a margin is a chain depends on the siblings, which only the rendered tree
# knows. It stays a review judgment, not a detector.











# Modern web-platform laws are review laws: the rendered tree, browser support,
# and component context decide whether a platform primitive is appropriate.












































































































# Five decorative devices a model reaches for by habit. Each is judged by what
# the mark does for the reader, not by its look, and each carries the
# constitutional law it serves: DENSITY (a mark that carries no information is
# noise) or LINEARITY (structure belongs to the element tree, not to glyphs
# between words). Rendered values stay operator-owned (RENDERED_VALUES), so none
# of these names a replacement colour, face or size. Detection lives once, here,
# so the laws and the false-positive census in test_design_marks.rb read the
# same patterns.
module DesignMarks
  module_function

  # Guarded: Law.load_all re-evaluates a changed law file in the same process.
  unless const_defined?(:ARROW_GLYPH)
    ARROW_GLYPH = "(?:\u2192|&rarr;|&#8594;|&#x2192;|->|&gt;&gt;|>>|▸|&#9656;|&#x25b8;)"
  end
  DOT_GLYPH = "(?:\u00B7|&middot;|&#183;|&#xb7;)" unless const_defined?(:DOT_GLYPH)

  # The innermost { … } blocks of a stylesheet, with their selector.
  def blocks(text)
    text.scan(/([^{};]*)\{([^{}]*)\}/m).map { |selector, body| [selector.strip, body] }
  end

  # px / rem / em value under the body size, or a named small step.
  def small_size?(body)
    value = body[/font-size\s*:\s*([^;}\n]+)/i, 1].to_s.strip
    return false if value.empty?
    return true if value.match?(/(?:--|\$)(?:font-?(?:size-?)?)?(?:2?xs|sm|small|caption|label|micro|tiny)\b/i)

    number = value[/\A([\d.]+)(rem|em|px)\b/i, 1]
    return false unless number

    value.match?(/px\b/i) ? number.to_f < 16 : number.to_f < 1
  end

  # Tracked all-caps eyebrows: uppercase and non-zero tracking together, on text
  # that is small or that the author named an eyebrow, kicker or overline.
  def eyebrow_blocks(text)
    blocks(text).select do |selector, body|
      next false unless body.match?(/text-transform\s*:\s*uppercase/i)

      # Heading case is structural, not a decorative label treatment. A heading
      # remains a finding even when it is large or has no tracking; proper case
      # is consistent across the levels and the page H1 carries the hierarchy.
      heading = selector.match?(/(?:\A|[\s,>])h[1-6](?=$|[\s,.:#\[])/i) ||
                selector.match?(/\.(?:page-title|section-title|empty-state-title|item-detail-title|amber-look-title|store-heading)\b/i)
      next true if heading

      next false unless body.match?(/letter-spacing\s*:\s*+(?!0(?:\.0+)?(?:px|r?em)?\s*[;}\n]|normal|inherit|initial|unset)[^;}\n]+/i)

      selector.match?(/eyebrow|kicker|overline/i) || small_size?(body)
    end
  end

  def eyebrow_class?(line) = line.match?(/class\s*[:=]\s*["'][^"']*\b(?:eyebrow|kicker|overline)\b/i)

  # A glyph that points at the next step, appended to the label of a link or button.
  def arrow_label?(line)
    return true if line.match?(%r{<(?:a|button)\b[^>]*>[^<]*?\s#{ARROW_GLYPH}\s*</(?:a|button)>}i)
    return true if line.match?(%r{<span\b[^>]*>\s*#{ARROW_GLYPH}\s*</span>}i)

    line.match?(/\b(?:link_to|button_to|submit|link_to_if)\b\s*\(?\s*(["'])[^"']*?\S\s*#{ARROW_GLYPH}\s*\1/)
  end

  # `A · B · C`: two or more dot separators between words, or a join(" · ").
  def dotted_meta?(line)
    return false if line.match?(/<title\b|<meta\b/i)
    return true if line.match?(/\.join\(\s*["'] ?#{DOT_GLYPH} ?["']\s*\)/)

    line.scan(/\S\s+#{DOT_GLYPH}\s+\S/).length >= 2
  end

  # A gradient painted as a surface. A fade to transparent is a functional edge
  # (a scroll hint, a scrim under text), so it is spared, as is a mask, a solid
  # fill and a hard-stop data bar.
  def gradient_wash?(line)
    return false unless line.match?(/(?:background(?:-image)?|--[\w-]+)\s*:[^;]*(?:linear|radial|conic)-gradient\(/i)

    return false if line.match?(/transparent|\bmask/i)

    # A colour used twice is a hard stop or a solid fill: a hairline or a data bar.
    !line.scan(/var\(--[\w-]+\)|#\h{3,8}\b/).tally.value?(2)
  end

  # Leading-zero counters and literal 0N labels: ornament on items that need no order.
  def ordinal_ornament?(line)
    return true if line.match?(/counter\([^)]*decimal-leading-zero/i)
    return true if line.match?(/content\s*:\s*["']0\d\b/)
    return true if line.match?(/>\s*0[1-9]\s*[\/.]?\s*</)

    line.match?(/(?:["']0<%=|["']%02d["']\s*%\s*\(?\s*\w*(?:index|idx|\bi\b)\b?|<%=\s*["']%02d["']\s*%\s*\(?[^%]*(?:index|idx|\+\s*1))/)
  end
end



















































































# Paragraph separation and the printed page (Bringhurst 2.3, Butterick, Tschichold). The
# rendered half of the paragraph Law is an adapter over a design_laws snapshot.
require_relative "../checks/support/rendered_design"

module Law
  module PageCss
    MM = { "mm" => 1.0, "cm" => 10.0, "in" => 25.4, "pt" => 25.4 / 72, "px" => 25.4 / 96 }.freeze
    CANON = { "top" => 1.5, "outer" => 2.0, "bottom" => 3.0 }.freeze
    SIDES = %w[top right bottom left].freeze
    # Which of the four sides each value of a 1-, 2-, 3- or 4-value margin shorthand sets.
    SHORTHAND = { 1 => [0, 0, 0, 0], 2 => [0, 1, 0, 1], 3 => [0, 1, 2, 1], 4 => [0, 1, 2, 3] }.freeze
    NONZERO = /\s*:\s*(?!0[;\s}]|0\z)[\d.]/
    INDENT = /text-indent#{NONZERO}/
    SPACED = /margin(?:-block(?:-start|-end)?|-top|-bottom)?#{NONZERO}/
    PAGE = /@page\s*(:left|:right|:first)?\s*\{([^{}]*)\}/
    MEASURE = /(?:max-)?(?:width|inline-size)\s*:\s*(\d+)ch/

    module_function

    def rules(src) = src.scan(/([^{}]*)\{([^{}]*)\}/).map { |selector, body| [selector.strip, body] }

    def paragraph?(selector) = selector.split(",").any? { |part| part.strip.match?(/(?:\A|[\s>+~])p\z/) }

    def line_at(src, offset) = src[0, offset].count("\n") + 1

    def mm(value) = value.to_f * MM.fetch(value[/[a-z]+\z/].to_s, 1.0)

    def margins(body)
      values = body[/(?:\A|[;\s])margin\s*:\s*([^;}]+)/, 1].to_s.split.map { |value| mm(value) }
      order = SHORTHAND.fetch(values.size, [])
      SIDES.each_with_index.to_h do |side, index|
        own = body[/margin-#{side}\s*:\s*([^;}]+)/, 1]
        [side, own ? mm(own) : values[order[index].to_i]]
      end
    end

    # inner, top, outer and bottom for a left or right page.
    def faces(pseudo, body)
      sides = margins(body)
      inner, outer = pseudo == ":left" ? sides.values_at("right", "left") : sides.values_at("left", "right")
      { "inner" => inner, "top" => sides["top"], "outer" => outer, "bottom" => sides["bottom"] }
    end

    def near?(value, ratio) = (value - ratio).abs <= ratio * 0.15

    def canon(pseudo, body)
      face = faces(pseudo, body)
      return if face.values.compact.size < 4
      ordered = face.values.each_cons(2).all? { |near, far| near < far }
      return "@page#{pseudo} margins are not inner < top < outer < bottom" unless ordered

      off = CANON.reject { |side, ratio| near?(face[side] / face["inner"], ratio) }
      "@page#{pseudo} margins stray from 2:3:4:6 (#{off.keys.join(", ")})" if off.any?
    end

    def matches(src, pattern) = src.to_enum(:scan, pattern).map { [Regexp.last_match, Regexp.last_match.begin(0)] }

    def page_findings(src)
      pages = matches(src, PAGE).filter_map { |page, at| (message = canon(page[1], page[2])) && [message, at] }
      wide = matches(src, MEASURE).reject { |width, _at| width[1].to_i.between?(55, 75) }
      pages + wide.map { |width, at| ["measure #{width[1]}ch is outside 55-75ch", at] }
    end

    def both_devices(src)
      rules = rules(src).select { |selector, _body| paragraph?(selector) || selector.match?(/\bp\s*\+\s*p\z/) }
      indent = rules.find { |_selector, body| body.match?(INDENT) }
      return [] unless indent && rules.any? { |_selector, body| body.match?(SPACED) }

      [{ line: line_at(src, src.index(indent[1])), message: "paragraphs are indented and spaced - choose one device" }]
    end

    def paragraphs(**fields) = %w[p.a p.b].map { |key| Deploy::RenderedDesign.element(key, pid: 1, **fields) }
  end

  P = PageCss

  
















  










end
