# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:700 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2d5c274f192ac13f
require_relative "master/law/universal"

Law.define(:DRY) do
  source "DRY - Don't Repeat Yourself"
  ask "Are two units expressing the same knowledge independently rather than sharing one authoritative source?"
  fix "Merge the duplicated knowledge or make one representation authoritative."
  bad <<~'X'
    timeout = 30; other_timeout = 30
  X
  good <<~'X'
    timeout = DEFAULT_TIMEOUT
  X
end
