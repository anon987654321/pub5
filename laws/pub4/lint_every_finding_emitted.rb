# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml LINT_EVERY_FINDING_EMITTED by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8d0a77154da56d68
require_relative "master/lib/master"

Law.define(:LINT_EVERY_FINDING_EMITTED) do
  source "pub4 MASTER/data/laws.yml LINT_EVERY_FINDING_EMITTED"
  practice "Soul.emit is called for every finding; a finding not emitted is a finding under APPLICATION_IS_UNIFORM_unrecorded_finding."
end
