# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml SACRED_AUTHORSHIP_autonomous_sacred_write by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b0b5d22357e36680
require_relative "master/lib/master"

Law.define(:SACRED_AUTHORSHIP_AUTONOMOUS_SACRED_WRITE) do
  source "pub4 MASTER/data/laws.yml SACRED_AUTHORSHIP_autonomous_sacred_write"
  practice "An automated writer touching a path declared sacred by soul.yml."
end
