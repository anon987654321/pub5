# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_NO_EXCLUDE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 07ec4763c3d42a62
require_relative "master/lib/master"

Law.define(:LINT_NO_EXCLUDE) do
  source "pub4 MASTER/data/laws.yml LINT_NO_EXCLUDE"
  practice "A law does not carry exclude, path, or path_pattern. A file's kind is a fact; the finding is made; the review resolution carries the reason and the expiry."
end
