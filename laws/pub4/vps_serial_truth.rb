# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:322 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 10bb4929d24633fe
require_relative "master/law/practice"

Law.define(:VPS_SERIAL_TRUTH) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    one SSH session, no parallel bin/ci. Production truth is vm23. Copy any
    edit made on the box back into git in the same session.
  TEXT
  fix "one SSH session, no parallel bin/ci."
  bad  "two parallel bin/ci runs"
  good "one session, one run"
end
