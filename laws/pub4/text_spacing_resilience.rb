# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:229 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 76300fa336670d8a
require_relative "master/law/rendered"

module Law
  Law.define(:TEXT_SPACING_RESILIENCE) do
    F.rendered(self, :TEXT_SPACING_RESILIENCE,
               source: "WCAG 1.4.12 Text Spacing, AA",
               fix: "Let text boxes grow (min-block-size, padding) instead of fixing height with overflow hidden.",
               bad: F.page(spacing: { "clipped" => ["span.chip"], "sideways" => false }),
               good: F.page(spacing: { "clipped" => [], "sideways" => false }))
  end
end
