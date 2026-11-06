# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1111 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8f02ff604d037243
require_relative "master/law/universal"

Law.define(:SILENCE_ON_SUCCESS) do
  source "Unix philosophy - Rule of Silence"
  ask "Does a successful operation emit output that the operator does not need?"
  fix "Report errors and meaningful state; stay quiet on ordinary success."
  bad <<~'X'
    puts "done"
  X
  good <<~'X'
    return unless error
  X
end
