# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml DENSITY_no_puts by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 998b107609174ed7
require_relative "master/lib/master"

Law.define(:DENSITY_NO_PUTS) do
  source "pub4 MASTER/data/laws.yml DENSITY_no_puts"
  practice "Library code writing to stdout; a CLI's own output is not a finding."
end
