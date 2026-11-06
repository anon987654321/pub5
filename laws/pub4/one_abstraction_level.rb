# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1305 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: cbe88b6120bd2087
require_relative "master/law/universal"

Law.define(:ONE_ABSTRACTION_LEVEL) do
  source "Clean Code - one level of abstraction per function"
  ask "Does this function mix policy-level operations with low-level representation or IO details?"
  fix "Keep each function at one conceptual level and delegate detail downward."
  bad <<~'X'
    def checkout; authorize_card; db.execute("INSERT INTO..."); render_html; end
  X
  good <<~'X'
    def checkout; authorize_card; persist_order; render_receipt; end
  X
end
