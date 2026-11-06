# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:810 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fe6acdf00323e354
require_relative "master/law/universal"

Law.define(:BROKEN_WINDOWS) do
  source "The Pragmatic Programmer - broken windows"
  ask "Is visible decay being left in place: dead code, stale references, broken links, or contradictory documentation?"
  fix "Fix visible decay when encountered instead of normalizing it."
  bad <<~'X'
    TODO: remove this dead branch
  X
  good <<~'X'
    return value unless value.nil?
  X
end
