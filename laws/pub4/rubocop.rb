# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/linters.rb:220 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4171b839784b5318
require_relative "master/lib/master"

Law.define(:rubocop) do
  source "pub4 MASTER/law/linters.rb:220"
  practice "RuboCop style/lint violation"
end
