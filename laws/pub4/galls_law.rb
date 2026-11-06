# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:664 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1f3c7415ea34856a
require_relative "master/law/universal"

Law.define(:GALLS_LAW) do
  source "Gall's Law - Systemantics (John Gall, 1975)"
  ask "Is a complex system being built from scratch without first proving a smaller working system?"
  fix "Start with the simplest working system, prove it, then extend."
  bad <<~'X'
    class Platform; def initialize; @services = 27.times.map { Service.new }; end; end
  X
  good <<~'X'
    class Platform; def call(input); MinimalPath.call(input); end; end
  X
end
