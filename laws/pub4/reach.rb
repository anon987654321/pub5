# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e32f48e318e45da1
require_relative "master/lib/master"

Law.define(:REACH) do
  source "pub4 MASTER/data/laws.yml REACH"
  practice "Whoever arrives can operate it - by keyboard, by screen reader, by voice, with a colour deficiency, on a phone at arm's length, in the environment the code runs in."
end
