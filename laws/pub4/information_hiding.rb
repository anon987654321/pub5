# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:738 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 69d843e6218bd131
require_relative "master/law/universal"

Law.define(:INFORMATION_HIDING) do
  source "Information hiding (David Parnas; Ousterhout)"
  ask "Do implementation details leak across a module boundary so changing one decision forces unrelated callers to change?"
  fix "Encapsulate the decision behind a stable interface."
  bad <<~'X'
    renderer.backend = :cairo; renderer.options[:cairo][:antialias] = true
  X
  good <<~'X'
    renderer.render(document, quality: :high)
  X
end
