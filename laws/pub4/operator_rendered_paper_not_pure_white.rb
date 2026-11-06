# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml OPERATOR_RENDERED_paper_not_pure_white by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3adceffb52e0d032
require_relative "master/lib/master"

Law.define(:OPERATOR_RENDERED_PAPER_NOT_PURE_WHITE) do
  source "pub4 MASTER/data/laws.yml OPERATOR_RENDERED_paper_not_pure_white"
  practice "A brand-export ground is not the declared ground."
end
