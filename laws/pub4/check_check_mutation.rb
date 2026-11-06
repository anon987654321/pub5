# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml check_mutation by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: dc747252a4cc60c4
require_relative "master/lib/master"

Law.define(:CHECK_CHECK_MUTATION) do
  source "pub4 MASTER/checks/checks.yml check_mutation"
  practice "Check check_mutation holds: ok: checks detect the defects they exist to prevent"
end
