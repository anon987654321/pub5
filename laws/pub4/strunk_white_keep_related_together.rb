# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_keep_related_together by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fc640aceeee97cdf
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_KEEP_RELATED_TOGETHER) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_keep_related_together"
  practice "Words that modify each other separated by intervening matter."
end
