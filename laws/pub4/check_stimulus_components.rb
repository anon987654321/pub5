# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml stimulus_components by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4bceccceaffa1fc8
require_relative "master/lib/master"

Law.define(:CHECK_STIMULUS_COMPONENTS) do
  source "pub4 MASTER/checks/checks.yml stimulus_components"
  practice "Check stimulus_components holds: Stimulus Components adoption check passed."
end
