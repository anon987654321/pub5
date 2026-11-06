# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:147 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2c786951f290fc39
require_relative "master/law/interface"

Law.define(:CAPABILITY_STATUS_MUST_BE_TRUTHFUL) do
  source "OpenBSD-style status reporting - unavailable capabilities are not ready"
  ask "Does a status, progress, success, pending, sent or delivered label, or a service readiness report, " \
      "claim a state the system has not observed: from a flag, an optimistic default, or before the " \
      "server or capability answered? State must derive from observed outcome and keep the failure reason."
  fix "Derive service state from the capability's actual health or retained error; report degraded or unavailable with the reason instead of ready."
  bad <<~'X'
    when "voice" then ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded" : "ready"
  X
  good <<~'X'
    when "voice"
      reason = Voice::Speech.last_error || Voice::Playback.last_error
      reason ? "degraded: #{reason}" : "ready"
  X
  detect do |text|
    text.match?(/when\s+["']voice["'][^\n]*ENV\[/) &&
      text.match?(/["']ready["']/)
  end
end
