# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:84 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d253cc4eabdb5e2a
require_relative "master/law/rendered"

module Law
  Law.define(:SIZE_COMPENSATED_SPACING) do
    F.rendered(self, :SIZE_COMPENSATED_SPACING,
               source: "Bringhurst 2.2.1 and 2.1.6-2.1.7; Butterick, line spacing 120-145%; Refactoring UI",
               fix: "Tighten leading (<= 1.25) and tracking (<= 0) on display type; give prose 1.4-1.6 and " \
                    "small type >= 1.4 and open tracking.",
               bad: F.page(F.el("h1", font_size: 40, line_height: 64)),
               good: F.page(F.el("h1", font_size: 40, line_height: 44, letter_spacing: -0.8)))
  end
end
