# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ffc45ae0e01937e6
require_relative "../lib/master"

# law/html.rb — every html law, one Law.define per law.
#
# IMG_ALT and LAZY_IMAGES live once, in the registry (web_laws.rb): both
# judge attributes of a tag, and a tag is not a line — the attribute-per-line
# spelling put alt= and loading= one line below the detector, so every
# multi-line <img> was a finding. The registry versions flatten tags first.









# ARIA_LABELS lives once, in the registry (web_laws.rb): its detector
# flattens multi-line tags and honours label-wrapping before judging, and the
# per-line duplicate here flagged every attribute-per-line control as nameless
# — the playlist transport bar carried six labels and six findings at once.

# SEMANTIC_ELEMENTS catches a div whose class is exactly a landmark name. This is
# the other half of divitis and the more common one: a div carrying nothing at
# all. It has no class, no id, no role and no data attribute, so it contributes
# no meaning to the document, no hook to the stylesheet and no target to a
# script. It exists because someone needed somewhere to hang a flex container
# and reached for the generic element.
#
# The fix is an element that says what the group is (section, article, header,
# ul) — or nothing. A wrapper whose only job was layout disappears once the
# parent becomes a grid, or once the stylesheet selects its children by
# structure.


























# One blank line separates two things. Two blank lines separate them by an
# amount nobody agreed on, and the amount is invisible — a reader cannot tell a
# deliberate double gap from a merged patch that left one behind, so the spacing
# stops carrying information the moment it varies.
#
# File-scoped because the defect is a relationship between lines: a single blank
# line is correct, and only its neighbour makes it wrong.



























# A class that restates its own tag adds a second name that only the
# stylesheet reads — and the second name is the one that rots.
#
# The first version of this law believed context could always carry the
# distinction ("main > header"), and named page-header as its bad fixture.
# The rendered DOM refuted that on 2026-08-21: probed over CDP with all four
# surfaces booted, .page-header's parent varies by page (main#main-content on
# search, section.channels-index on channels), and the marketplace front page
# lays out FOUR header species at once — page-header, composer-header,
# marketplace-top-offers-header and the market-hero that sits as main's
# direct child and must NOT share their styling. No context selector
# discriminates what those prefixes discriminate; the prefix is the honest
# name for WHICH header this is, exactly the live-feed case the paragraph
# below always allowed.
#
# So the law now claims only what it can defend: a class whose distinguishing
# half is pure filler (content-, inner-, wrapper-, -area, -block…) restates
# the tag and goes. A class whose prefix names one of several coexisting
# species stays — that discrimination is its job.
#
# A section classed live-feed describes itself and stays; a section classed
# content-section restates itself and goes.








# HTML_LANG lives once, in the registry (web_laws.rb): it reads through
# tag_source, so an `<html` inside a comment, a string or an ERB expression
# is prose about the tag, not the tag. This bare line regex had no such
# filter — the tag_source family is why ARIA_LABELS and IMG_ALT retired the
# same way.







































# A document that declares no encoding leaves the browser to guess, and the
# guess is wrong often enough that WHATWG requires the declaration.
#
# Only a document can carry one. A partial has no head to put it in, so the
# earlier detector — anything lacking the meta tag — fired on all 423 partials
# in RAILS and on 5 layouts, and the 423 could not have complied if they tried.
# The guard asks whether this file is a document before asking whether it
# declares its encoding.













# A script or style block written into a template is the html half of
# NO_MULTIPLE_LANGUAGES, split out so its detector can say what it means. The
# parent rule caught it by matching a language marker, which also matched every
# ERB tag in every view.
#
# A strict Content-Security-Policy cannot fingerprint an inline block without a
# nonce, the cache cannot hold it apart from the page carrying it, and every
# tool that reads stylesheets and scripts as files walks straight past it. A tag
# with src or href suffers none of that, so this ignores them.




































# A link someone is paid for says so to the machine as well as to the reader:
# rel="sponsored" is how Google asks paid and affiliate links to be marked, and
# a commission link without it reads as an editorial recommendation. The
# commercial ones are the links that carry an affiliate URL or the
# outbound-click controller, which is how the apps attribute a click to a
# merchant. The visible label beside the link is VISUAL_DISCLOSURE_PROMINENCE's.





















# A class should name what a thing is, not what it currently looks like. Words
# like dim, bold, small and red describe one rendering decision, so changing
# that decision means editing every view carrying the word, and the markup ends
# up asserting a colour it cannot guarantee.
#
# In this tree the cost already shows. The word dim sits on 301 elements across
# three apps and resolves to a different colour in each: --text-secondary in
# brgen, --color-grey-text in amber, --text-secondary in bsdports. The built
# stylesheets carry seven, six and four rules matching it. Two of amber's three
# bare declarations never take effect, and two of bsdports' do not either — they
# lose to a later rule of equal specificity, so the earlier ones are dead weight
# that would come alive if anyone reordered an @use.
#
# Nothing in the markup says which of those a given element asked for, because
# the markup asked only for "dim".
#
# The fix is often an element, not another class: small for a side comment,
# strong and em for emphasis, time for a timestamp. Those carry meaning to
# assistive technology as well as to the stylesheet, and no second declaration
# can quietly override them.



















# A keyboard reader lands on the first focusable thing on the page and tabs
# through the whole navigation before reaching the content, on every page. The
# skip link is the bypass WCAG 2.4.1 asks for.
#
# It belongs to the layout, which is the only file that owns the first focusable
# element. The earlier detector — anything not mentioning a skip target — fired
# on all 423 partials in RAILS, none of which can hold one, and buried the 5
# layouts where the question is real.
# The registry twin knew two more things, ported with its retirement: only
# layouts own the first focusable element, and a mailer layout is not a page
# — no viewport to skip past, no #main-content to land on; both findings
# this rule ever produced in RAILS were mailer layouts.










# TAG_HELPER_OVER_MARKUP is retired, not moved. Its detector matched
# `<p><%= ... %></p>` and its siblings; PREFER_TAG_HELPERS in the registry
# (law/web.rb, SIMPLE_WRAPPER_TAG_RE) is a strict
# superset — the same shape plus div, span, li and label, and tolerant of
# attributes. Measured over 536 RAILS views: every one of this rule's 292
# findings was also one of the registry's, so it only ever double-reported.
#
# The reasoning it carried is kept, because it is the argument for the rule
# that survives: a tag around one expression leaves for Ruby, returns, and
# closes in HTML -- four context switches to emit one line. The tag builder
# writes the same thing as one expression, a third shorter, impossible to
# leave unclosed, escaping its attributes by construction rather than by the
# author remembering to.










# The design-book Laws over markup (Butterick, Krug, Norman, WCAG 2.x). Their rendered halves
# are adapters over a design_laws snapshot (Deploy::RenderedDesign), proved the same way.
require_relative "../checks/support/rendered_design"

module Law
  module Markup
    SNAP = Deploy::RenderedDesign
    VIEWS = Regexp.union(/\.(?:html\.)?erb\z|\.html\z/, SNAP::SNAPSHOT)
    TEMPLATES = %r{\.(?:html\.)?erb\z|\.html\z}
    PERSONAL = /e?mail|phone|\btel|telefon|mobil|name|navn|given|family|address|adresse|street|postal|
               postnummer|zip|city|country|username|brukernavn|password|passord|otp|one_time|cc_|card|
               (?:\A|_)(?:kode|land|sted|gate)(?:\z|_)/xi
    FIELD = /\b(?:text|email|telephone|phone|password|number|search|url)_field(?:_tag)?\b|<input\b/

    NUMERIC = /postnummer|postal|zip|otp|one_time|(?:\A|_)kode(?:\z|_)/i
    LABEL = /\A\s*(?:E-?post|Telefon|Tlf|Pris|Dato|Email|Phone|Price|Date)\s*:?\s*\z/i
    SELF_EVIDENT = /<%=\s*(?:mail_to|phone_to|number_to_currency|time_tag|l)\b/
    ACTION = /(?:button_to|\.submit|button_tag)\s*\(?\s*((?:t\(\s*)?["'][^"']+["']\)?)|
              link_to\s*\(?\s*((?:t\(\s*)?["'][^"']+["']\)?)(?=.*class:\s*["'][^"']*\bbutton)/x
    ICONS = %r{<svg\b.*?</svg>|<img\b[^>]*>|<i\b[^>]*></i>|<%=\s*(?:icon|inline_svg\w*|svg_tag|image_tag)\b.*?%>}m

    module_function

    def set_to(attribute, value) = /#{attribute}(?::|=)\s*["']#{value}/

    def continues?(text) = text.rstrip.end_with?(",", "(") || (text.include?("<input") && !text.include?(">"))

    # A helper call or tag that continues over the next lines, joined into one statement.
    def statements(src, opener)
      lines = src.lines
      lines.each_index.select { |index| lines[index].match?(opener) }.map do |index|
        text = lines[index].dup
        lines[index + 1, 6].to_a.each do |more|
          break unless continues?(text)

          text << more
        end
        [text.gsub(/\s+/, " "), index + 1]
      end
    end

    def field_name(text)
      text[/_field(?:_tag)?\s*\(?\s*:?["']?(\w+)/, 1] || text[/\bname=["']([^"']+)/, 1] || text[/\bid=["']([^"']+)/, 1]
    end

    def purpose(text)
      return if text.match?(/type=["']?(?:hidden|submit|button|checkbox|radio)/)

      name = field_name(text).to_s
      return unless name.match?(PERSONAL)
      return "#{name} turns autocomplete off - name its purpose (error)" if text.match?(set_to("autocomplete", "off"))
      return "#{name} asks for personal data with no autocomplete token" unless text.include?("autocomplete")

      "#{name} wants inputmode numeric (info)" if name.match?(NUMERIC) && !text.match?(set_to("inputmode", "numeric"))
    end

    def words(label) = label.to_s.gsub(/%\{\w+\}|<[^>]+>/, " ").split.size

    def locale_file(file)
      YAML.safe_load_file(file, aliases: true) || {}
    rescue Psych::Exception # scan: intentional - an unreadable locale resolves no label; YAML_SYNTAX reports it
      {}
    end

    # t("absolute.key") read from the app's nb locale; a literal is its own label.
    def label(raw, path)
      key = raw[/\At\(\s*["']([\w.]+)["']/, 1] or return raw[/\A["']([^"']+)["']/, 1]
      root = path.to_s[%r{\A.*?/(?:RAILS/[^/]+|MASTER/web)(?=/)}] or return
      Dir[File.join(root, "config/locales/nb*.yml")].each do |file|
        found = locale_file(file).dig("nb", *key.split("."))
        return found if found.is_a?(String)
      end
      nil
    end

    def action_label(line)
      button = line[%r{<button\b[^>]*>([^<]{2,})</button>}, 1]&.then { |text| "\"#{text.strip}\"" }
      line.match(ACTION)&.captures&.compact&.first || button
    end

    def icon_only?(inner)
      rest = inner.gsub(ICONS, "").gsub(/<[^>]+>/, "")
      rest.strip.empty? && rest != inner
    end

    def icon_named?(tag)
      SNAP::AccessLaws.icon_words.include?(SNAP::AccessLaws.normal(tag[/aria-label=["']([^"']+)/, 1]))
    end

    def rendered(id) = ->(text, file) { SNAP.findings(id, text, file).map { |hit| finding(**hit) } }

    def page(*elements) = SNAP.fixture(elements:)

    # One ERB output tag around a Ruby expression, for the fixtures.
    ERB_TAG = [
      "<%= ",
      " %>",
    ].freeze

    def erb(code) = "#{ERB_TAG.first}#{code}#{ERB_TAG.last}\n"

    def control(key, **fields) = SNAP.element(key, interactive: true, **fields)

    def named(name, visible) = control("button", visible_text: visible, name:, attrs: { "aria-label" => name })

    def paste_blocker(line, auth)
      return "paste is blocked on a sign-in field" if line.match?(/\bonpaste\s*=|paste->/)
      off = line.match?(/password/i) && line.match?(set_to("autocomplete", "off"))
      return "password field turns autofill off" if off

      "a CAPTCHA on sign-in with no alternative (warning)" if auth && line.match?(/g-recaptcha|h-captcha|captcha/i)
    end

    def name_mismatch(line)
      norm = SNAP::AccessLaws.method(:normal)
      tag = line.match(%r{<(button|a)\b[^>]*aria-label=["']([^"']+)["'][^>]*>([^<]+)</\1>})
      keys = line.match(/\bt\(\s*["']([\w.]+)["']\).*aria:\s*\{\s*label:\s*t\(\s*["']([\w.]+)["']/)
      hidden = tag && !norm.(tag[2]).include?(norm.(tag[3]))
      return "aria-label #{tag[2].inspect} hides the visible #{tag[3].strip.inspect}" if hidden

      "visible text #{keys[1]} and name #{keys[2]} are different keys" if keys && keys[1] != keys[2]
    end

    def unneeded_label(lines, index)
      tag = lines[index].match(%r{<(dt|th|span|strong|b|label)\b([^>]*)>([^<]*)</\1>}) or return
      return if tag[2].match?(/visually-hidden|sr-only/) || !tag[3].match?(LABEL)

      follows = lines[index][tag.end(0)..].to_s + lines[index + 1].to_s
      "#{tag[3].strip.inspect} labels data that says what it is" if follows.match?(SELF_EVIDENT)
    end
  end

  M = Markup

  











  





















  



















  

















  

























  



















  
















  

















end
