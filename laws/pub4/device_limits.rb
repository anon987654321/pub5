# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:345 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 89dfbd71f07c5776
require_relative "master/law/practice"

Law.define(:DEVICE_LIMITS) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    heavy work belongs on the VPS. The Mac edits and HTTP-probes; browser
    checks run on the deploy host unless explicitly forced local.
  TEXT
  fix "heavy work belongs on the VPS."
  bad  "browser checks on the laptop"
  good "browser checks on the deploy host"
end
