# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:206 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f9edfff563b81d04
require_relative "master/law/rendered"

module Law
  Law.define(:NON_TEXT_CONTRAST) do
    F.rendered(self, :NON_TEXT_CONTRAST,
               source: "WCAG 1.4.11 Non-text Contrast, AA 3:1; WCAG 2.2 SC 2.4.13; operator 2026-11-06: 3:1",
               fix: "Give inputs, buttons, acting icons and focus rings 3:1 against their surroundings.",
               bad: F.page(F.input([34, 34, 34, 1])), good: F.page(F.input([118, 118, 118, 1])))
  end
end
