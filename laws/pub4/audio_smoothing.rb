# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1135 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 76b80b4677c92982
require_relative "master/law/universal"

Law.define(:AUDIO_SMOOTHING) do
  source "MASTER-native - audio smoothing"
  ask "Do visual elements jump erratically because raw audio samples drive motion directly?"
  fix "Smooth or envelope audio-derived control values before applying visual motion."
  bad <<~'X'
    scale = fft[12]
  X
  good <<~'X'
    scale = smoothing.update(fft[12])
  X
end
