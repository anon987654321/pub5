# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1195 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 30ef5d93d2314b48
require_relative "master/law/universal"

Law.define(:ERROR_CONTEXT) do
  source "Context-rich error handling"
  ask "Does an error or rejection omit the context needed to locate the cause and decide the next action?"
  fix "Include relevant operation, subject, and cause without leaking secrets."
  bad <<~'X'
    raise Error, "failed"
  X
  good <<~'X'
    raise Error, "invoice #{invoice.id}: payment authorization failed"
  X
end
