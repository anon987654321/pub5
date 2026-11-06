# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:551 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fb5ada751670e25a
require_relative "master/law/html"

module Law
  ::Law.define(:EMPHASIS_ONE_DEVICE) do
    source "Butterick, bold or italic sparingly, never both; underline only for links"
    tags %i[TYPOGRAPHY]
    path Regexp.union(M::VIEWS, /\.s?css\z/)
    fix "Emphasise with one device: <strong> or <em>, never both; keep underline for links."
    bad "<p><strong><em>Gratis levering</em></strong></p>\n"
    good "<p><strong>Gratis levering</strong></p>\n"
    nested = %r{<(?:strong|b)>\s*<(?:em|i)>|<(?:em|i)>\s*<(?:strong|b)>}
    check do |src, _path|
      src.each_line.with_index(1).filter_map do |line, n|
        finding(line: n, message: "bold and italic at once") if line.match?(nested)
      end
    end
    adapter(:whole_file, languages: %i[css scss], bad: ".deal { font-weight: 700; font-style: italic; }\n",
                         good: ".deal { font-weight: 700; }\n") do |src, _file|
      src.scan(/[^{}]*\{([^{}]*)\}/).filter_map do |(body)|
        next unless body.match?(/font-weight:\s*(?:bold|[6-9]00)/) && body.match?(/font-style:\s*italic/)

        finding(line: src[0, src.index(body)].count("\n") + 1, message: "a rule sets bold and italic at once")
      end
    end
    underlined = M::SNAP.element("span.deal", decoration: "underline")
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE, bad: M.page(underlined),
                          good: M.page(M::SNAP.element("span.deal")), &M.rendered(:EMPHASIS_ONE_DEVICE))
  end
end
