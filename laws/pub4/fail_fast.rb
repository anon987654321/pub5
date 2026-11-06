# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1355 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a453c12f8a5e20ef
require_relative "master/law/universal"

Law.define(:FAIL_FAST) do
  source "Fail Fast (Jim Shore)"
  ask "Does the system defer reporting a known invalid state instead of stopping at the point it is detected?"
  fix "Reject invalid state immediately with actionable context."
  bad <<~'X'
    result = parse(input); use(result) if result.valid?
  X
  good <<~'X'
    raise InvalidInput, result.error unless parse(input).ok?
  X
end
