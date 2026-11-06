# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:82 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 64e92d5d0dd0d1f9
require_relative "master/law/interface"

Law.define(:VOICE_FAILURES_ARE_ACTIONABLE) do
  path "MASTER/lib/voice/"
  source "OpenBSD-style explicit failure reporting - degraded capability is state, not noise"
  ask "When synthesis, transport, or playback fails, does the runtime produce one bounded actionable state, preserve a useful last_error, and use the declared fallback chain without replaying or spawning uncontrolled work? Return CLEAN when the failure path is already explicit and bounded."
  fix "Return an explicit failure/result, retain the reason for /status or /doctor, rate-limit repeated diagnostics, and fall through only to declared voice/audio fallbacks."
  bad <<~'X'
    rescue StandardError
      warn e
      nil
    end
  X
  good <<~'X'
    rescue StandardError => e
      @last_error = "#{e.class}: #{e.message}"
      warn_once("voice0: unavailable - #{@last_error}")
      fallback_or_false
    end
  X
end
