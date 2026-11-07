# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/meta.rb:121 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4fb9293e1bfcddb8
require_relative "master/lib/master"

Law.define(:law_coverage) do
  source "pub4 MASTER/law/meta.rb:121"
  practice "Law subclass has no corresponding test file"
end
