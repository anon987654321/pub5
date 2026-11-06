# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:798 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 131af87a2c38f0ec
require_relative "master/law/universal"

Law.define(:ETC) do
  source "The Pragmatic Programmer - Easier To Change"
  ask "Does this decision unnecessarily close future options or make change expensive?"
  fix "Prefer decoupled, replaceable, reversible choices where costs are comparable."
  bad <<~'X'
    class Report < VendorSpecificReportBase; end
  X
  good <<~'X'
    class Report; def render(formatter); formatter.render(self); end; end
  X
end
