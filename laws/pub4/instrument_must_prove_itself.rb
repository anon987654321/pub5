# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1752 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bee95c9c83a9c85d
require_relative "master/law/universal"

Law.define(:INSTRUMENT_MUST_PROVE_ITSELF) do
  source "MASTER constitutional self-test policy"
  ask "Does every detector or check that can influence a decision have a known-positive and known-negative proof, or an explicit semantic evaluation path?"
  practice "A measuring instrument must demonstrate what it catches and what it spares before its findings can drive automatic action."
  fix "Add polarity fixtures or a semantic evaluation contract before trusting the instrument."
  bad "A new veto regex is enabled with no false-positive fixture."
  good "The detector has a failing fixture, a clean fixture, and its evaluation surface is covered by a check."
end
