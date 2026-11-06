# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RAILS_DOCTRINE_beautiful_code by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d709344c6f183c95
require_relative "master/lib/master"

Law.define(:RAILS_DOCTRINE_BEAUTIFUL_CODE) do
  source "pub4 MASTER/data/laws.yml RAILS_DOCTRINE_beautiful_code"
  practice "Code that works but cannot be read."
end
