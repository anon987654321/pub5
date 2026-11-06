# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_form_label by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3aece7a201b128a2
require_relative "master/lib/master"

Law.define(:REACH_FORM_LABEL) do
  source "pub4 MASTER/data/laws.yml REACH_form_label"
  practice "A form input with no label."
end
