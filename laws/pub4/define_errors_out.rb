# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1627 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: beb0a4feee53c69f
require_relative "master/law/universal"

Law.define(:DEFINE_ERRORS_OUT) do
  source "A Philosophy of Software Design - define errors out of existence"
  ask "Is the interface handling errors that could instead be prevented by making invalid states unrepresentable or normalizing inputs earlier?"
  fix "Redesign the interface so the problematic state cannot arise on the normal path."
  bad <<~'X'
    if config[:timeout].nil?; config[:timeout] = 30; end
  X
  good <<~'X'
    timeout = TimeoutValue.default(config[:timeout])
  X
end
