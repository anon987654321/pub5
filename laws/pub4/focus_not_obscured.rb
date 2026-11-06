# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:148 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1c6f2f8231a77153
require_relative "master/law/rendered"

module Law
  Law.define(:FOCUS_NOT_OBSCURED) do
    F.rendered(self, :FOCUS_NOT_OBSCURED,
               source: "WCAG 2.2 SC 2.4.11 Focus Not Obscured (Minimum), AA, and 2.4.12 (Enhanced), AAA",
               fix: "Give html scroll-padding-block equal to the sticky bars' height so focus never lands under them.",
               bad: F.page(focus: [{ "key" => "a.more", "covers" => [{ "key" => "header", "share" => 1.0 }] }]),
               good: F.page(focus: [{ "key" => "a.more", "covers" => [] }]))
    bars = /header|nav|tab-bar|\bbar\b/
    adapter(:whole_file, languages: %i[css scss], bad: "header { position: sticky; top: 0; }\n",
                         good: "html { scroll-padding-block: 52px; }\nheader { position: sticky; }\n") do |src, file|
      pinned = /position\s*:\s*(?:sticky|fixed)/
      sticky = src.scan(/([^{}]*)\{([^{}]*)\}/).find { |selector, body| selector.match?(bars) && body.match?(pinned) }
      siblings = File.file?(file.to_s) ? Dir[File.join(File.dirname(file), "**/*.{css,scss}")].first(200) : []
      padded = src.include?("scroll-padding") || siblings.any? { |other| File.read(other).include?("scroll-padding") }
      next [] if sticky.nil? || padded

      [finding(line: src[0, src.index(sticky[1])].count("\n") + 1, message: "sticky chrome with no scroll-padding")]
    end
  end
end
