# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1269 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 63b36aa5cc658e91
require_relative "master/law/universal"

Law.define(:ONE_JOB) do
  source "SRP / Unix philosophy - do one thing"
  ask "Does this module handle unrelated responsibilities instead of one coherent job?"
  fix "Give the module one job and compose it with neighboring modules."
  bad <<~'X'
    class UserService; def find; end; def email; end; def export; end; end
  X
  good <<~'X'
    class UserFinder; end; class UserMailer; end; class UserExporter; end
  X
end
