# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:640 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 448946ec2083c8e6
require_relative "master/law/universal"

Law.define(:DECOUPLE) do
  source "The Pragmatic Programmer - decoupling"
  ask "Are there implicit couplings between modules that should be explicit dependencies?"
  fix "Inject dependencies through explicit boundaries; avoid hidden global state."
  bad <<~'X'
    Mailer.send(UserStore.fetch(id))
  X
  good <<~'X'
    def initialize(mailer:, user_store:)
  X
end
