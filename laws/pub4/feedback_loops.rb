# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1653 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 36fef85701af1ddc
require_relative "master/law/universal"

Law.define(:FEEDBACK_LOOPS) do
  source "Nielsen feedback / checkpoint principle"
  ask "Does this perform substantial work without reporting progress, checkpoints, or a recoverable state?"
  fix "Add meaningful progress or checkpoints proportional to operation duration and risk."
  bad <<~'X'
    backup.run # 20 minutes, no checkpoints
  X
  good <<~'X'
    backup.run { |checkpoint| emit(checkpoint) }
  X
end
