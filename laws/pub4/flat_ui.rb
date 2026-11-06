# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/practice.rb:484 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c1154e87771ba150
require_relative "master/law/practice"

Law.define(:FLAT_UI) do
  source "MASTER constitution (soul.yml absolute.rules)"
  practice <<~TEXT
    Flat Design - uniform size at rest; depth only when pixels collectively
    resemble a 3D model.
  TEXT
  fix "Flat Design - uniform size at rest;"
  bad  "a raised card with a shadow"
  good "a flat surface with a border"
end
