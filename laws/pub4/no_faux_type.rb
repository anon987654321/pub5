# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:93 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 843204184e472a8f
require_relative "master/law/rendered"

module Law
  Law.define(:NO_FAUX_TYPE) do
    F.rendered(self, :NO_FAUX_TYPE,
               source: "Bringhurst 2.1.9, don't alter letter shapes without cause; Butterick, no fake small caps",
               fix: "Ask only for the weights and caps the shipped faces carry on every platform (400/700 for " \
                    "Arial) and set font-synthesis: none.",
               bad: F.snap(fonts: [F.font(700, "ArialMT")]), good: F.snap(fonts: [F.font(700, "Arial-BoldMT")]))
text = /(?:\A|[\s,>])(?:h[1-6]|p|a|span|li|label|strong|em)\b|title|label|text/
stretch = /transform\s*:[^;]*scale[XY]\(|font-stretch\s*:\s*(?!normal|100%)/
adapter(:whole_file, languages: %i[css scss], bad: "h1 { transform: scaleX(1.2); }\n",
                     good: "h1 { font-weight: 700; }\n") do |src, _file|
  src.scan(/([^{}]*)\{([^{}]*)\}/).filter_map do |selector, body|
    next unless body.match?(stretch) && selector.match?(text)

        finding(line: src[0, src.index(body)].count("\n") + 1, message: "#{selector.strip} stretches its letters")
      end
    end
  end
end
