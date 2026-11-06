# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml RENAME by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8abc254986b835d1
require_relative "master/lib/master"

Law.define(:RENAME) do
  source "pub4 MASTER/data/laws.yml RENAME"
  practice "Name present meaning. Rename when the existing name misleads."
end
