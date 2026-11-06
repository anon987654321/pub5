# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml VISUAL_CONTRAST_WCAG_AA by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5c0dc4044496b2cb
require_relative "master/lib/master"

Law.define(:VISUAL_CONTRAST_WCAG_AA) do
  source "pub4 MASTER/data/laws.yml VISUAL_CONTRAST_WCAG_AA"
  practice "Every audited ad text/background pair meets WCAG AA contrast thresholds in the token contract and in rendered evidence."
end
