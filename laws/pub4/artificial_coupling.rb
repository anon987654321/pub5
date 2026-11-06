# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1087 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 39eef8bb54d4b96e
require_relative "master/law/universal"

Law.define(:ARTIFICIAL_COUPLING) do
  source "The Pragmatic Programmer - avoid artificial coupling"
  ask "Are unrelated concepts coupled merely because they share a container, proximity, or formatting convention?"
  fix "Separate unrelated concerns and couple only through meaningful interfaces."
  bad <<~'X'
    settings = { audio: audio, billing: billing, css: css }
  X
  good <<~'X'
    Audio::Settings.new(audio); Billing::Settings.new(billing)
  X
end
