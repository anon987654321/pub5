# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1147 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d2d1858f16b72b4c
require_relative "master/law/universal"

Law.define(:GRACEFUL_LOAD) do
  source "Web performance - progressive loading"
  ask "Does this run at full quality until resource exhaustion instead of degrading in measured stages?"
  fix "Start with a safe baseline and progressively add quality within resource bounds."
  bad <<~'X'
    renderer.render(quality: :ultra)
  X
  good <<~'X'
    quality = budget.available? ? :full : :low; renderer.render(quality:)
  X
end
