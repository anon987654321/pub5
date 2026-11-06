# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_no_eyebrow_label by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c690609b2617e6ff
require_relative "master/lib/master"

Law.define(:DENSITY_NO_EYEBROW_LABEL) do
  source "pub4 MASTER/data/laws.yml DENSITY_no_eyebrow_label"
  practice "A tracked all-caps line above a heading that restates it."
end
