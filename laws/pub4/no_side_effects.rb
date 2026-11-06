# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1391 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cb927112b5026c03
require_relative "master/law/universal"

Law.define(:NO_SIDE_EFFECTS) do
  source "Functional programming / Clean Code"
  ask "Does this function silently modify external state in addition to returning its conceptual result?"
  fix "Separate side effects from pure transformation where practical."
  bad <<~'X'
    def normalize(x); DB.write(x.strip); x.strip; end
  X
  good <<~'X'
    def normalize(x); x.strip; end
  X
end
