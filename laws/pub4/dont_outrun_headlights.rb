# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:834 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 980d748c5aff5ab6
require_relative "master/law/universal"

Law.define(:DONT_OUTRUN_HEADLIGHTS) do
  source "The Pragmatic Programmer - don't outrun your headlights"
  ask "Is the design specifying distant hypothetical scenarios more precisely than current evidence allows?"
  fix "Take small deliberate steps and reassess after each measured result."
  bad <<~'X'
    design_for_1000000_users = FutureArchitecture.new
  X
  good <<~'X'
    serve_current_users = SimpleApp.new
  X
end
