# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml OPERATOR_RENDERED_aesthetic_substitution by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 01fa4cf15d721840
require_relative "master/lib/master"

Law.define(:OPERATOR_RENDERED_AESTHETIC_SUBSTITUTION) do
  source "pub4 MASTER/data/laws.yml OPERATOR_RENDERED_aesthetic_substitution"
  practice "The system substituted its own aesthetic choice."
end
