# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/linters.rb:273 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 36b62f82a6156fe7
require_relative "master/lib/master"

Law.define(:reek) do
  source "pub4 MASTER/law/linters.rb:273"
  practice "Reek code smell detected"
end
