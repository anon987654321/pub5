# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_IDS_UNIQUE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b2cc09cc9f3ce3c7
require_relative "master/lib/master"

Law.define(:LINT_IDS_UNIQUE) do
  source "pub4 MASTER/data/laws.yml LINT_IDS_UNIQUE"
  practice "Every law id is unique across the file."
end
