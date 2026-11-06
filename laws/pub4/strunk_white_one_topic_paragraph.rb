# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml STRUNK_WHITE_one_topic_paragraph by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fc9dd3dc03c6d184
require_relative "master/lib/master"

Law.define(:STRUNK_WHITE_ONE_TOPIC_PARAGRAPH) do
  source "pub4 MASTER/data/laws.yml STRUNK_WHITE_one_topic_paragraph"
  practice "A paragraph with more than one idea."
end
