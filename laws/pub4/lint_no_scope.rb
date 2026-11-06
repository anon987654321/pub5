# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_NO_SCOPE by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5f18525686308038
require_relative "master/lib/master"

Law.define(:LINT_NO_SCOPE) do
  source "pub4 MASTER/data/laws.yml LINT_NO_SCOPE"
  practice "A law does not carry applies_to or domain. A universal law does not say where it applies; if a file contains the pattern, the law catches it. If it does not, there is no finding."
end
