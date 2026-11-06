# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/checks/checks.yml master_tts by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f60bb8907ef1b128
require_relative "master/lib/master"

Law.define(:CHECK_MASTER_TTS) do
  source "pub4 MASTER/checks/checks.yml master_tts"
  practice "Check master_tts holds: MASTER TTS check passed."
end
