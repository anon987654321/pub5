# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/semantic.rb:451 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7f74385ef3c50d25
require_relative "master/lib/master"

Law.define(:semantic) do
  source "pub4 MASTER/law/semantic.rb:451"
  practice "LLM-based rule review (violations + opportunities)"
end
