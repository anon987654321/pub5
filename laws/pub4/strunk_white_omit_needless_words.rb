# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_omit_needless_words by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bdfbeb68f433d03a
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_OMIT_NEEDLESS_WORDS) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_omit_needless_words"
  practice "A qualifier that does not change the meaning."
end
