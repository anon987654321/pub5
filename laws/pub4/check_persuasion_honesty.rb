# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml persuasion_honesty by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e5879dc7d8b44f3f
require_relative "master/lib/master"

Law.define(:CHECK_PERSUASION_HONESTY) do
  source "pub4 MASTER/checks/checks.yml persuasion_honesty"
  practice "Check persuasion_honesty holds: Persuasion honesty check passed."
end
