# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:516 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 906b34cd29854b27
require_relative "master/law/universal"

Law.define(:CONSISTENT_ERROR_STRATEGY) do
  source "MASTER-native (uniform error handling)"
  ask "Does this module mix Result objects, exceptions, and nil returns for equivalent failure paths?"
  fix "Choose one error strategy per module and use it consistently."
  bad <<~'X'
    def find(id); raise NotFound if missing; end
  X
  good <<~'X'
    def find(id); Result.ok(record) or Result.err(:not_found); end
  X
end
