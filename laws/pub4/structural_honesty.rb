# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:762 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 01b303f309464276
require_relative "master/law/universal"

Law.define(:STRUCTURAL_HONESTY) do
  source "MASTER-native - structure mirrors intent"
  ask "Does the artifact's structure contradict the conceptual shape of the problem?"
  fix "Align modules, sections, layout, and boundaries with the actual domain."
  bad <<~'X'
    misc/helpers/user_and_audio_and_css.rb
  X
  good <<~'X'
    users/user.rb; audio/track.rb; ui/theme.css
  X
end
