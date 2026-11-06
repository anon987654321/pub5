# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:724 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 81e71c28dba8022c
require_relative "master/law/universal"

Law.define(:LEAST_ASTONISHMENT) do
  source "Principle of Least Astonishment"
  ask "Do names, APIs, or behavior contradict what a reasonable reader would expect?"
  fix "Rename or reshape the interface so behavior matches its apparent meaning."
  bad <<~'X'
    users.empty? # returns true when users exist
  X
  good <<~'X'
    users.present?
  X
end
