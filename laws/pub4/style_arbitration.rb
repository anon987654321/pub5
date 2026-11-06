# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STYLE_ARBITRATION by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a4bcc499f01bdc34
require_relative "master/lib/master"

Law.define(:STYLE_ARBITRATION) do
  source "pub4 MASTER/data/laws.yml STYLE_ARBITRATION"
  practice "Reviewers adjudicate declared contracts and evidence, not taste; aesthetic decisions remain with the operator under RENDERED_VALUES."
end
