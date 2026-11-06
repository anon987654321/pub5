# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:102 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ff9821a4315616ca
require_relative "master/law/interface"

Law.define(:CLI_ANALYZE_TARGET_ROUTING) do
  path "MASTER/data/patterns.yml"
  source "MASTER CLI - deterministic repository analysis targets"
  scope :file
  ask "Does natural-language analysis of an explicit repository path enter the deterministic operator route instead of falling through to the model and guessing about file existence?"
  fix "Register analyze/analyse/inspect with a path capture and map it to the canonical review route."
  bad <<~'X'
    commands:
      review:
        patterns:
        - "\\b(?:review)\\s+(.+)"
  X
  good <<~'X'
    infer:
      commands:
        analyze:
          patterns:
          - "\\b(?:analyze|analyse|inspect)\\s+([\\w./-]+)"
          capture: path
  X
  detect do |text|
    section = text[/^    analyze:\s*\n(.*?)(?=^    [a-z][a-z0-9_-]*:\s*$|\z)/m, 1].to_s
    section.empty? || !section.match?(/analyze|analyse|inspect/) || !section.match?(/capture:\s*path/)
  end
end
