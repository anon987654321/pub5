# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_focus_visible by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6387d0a987308698
require_relative "master/lib/master"

Law.define(:REACH_FOCUS_VISIBLE) do
  source "pub4 MASTER/data/laws.yml REACH_focus_visible"
  practice "A focusable element with no visible focus state."
end
