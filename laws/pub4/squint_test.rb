# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:266 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1cff2412b42923ca
require_relative "master/law/universal"

Law.define(:SQUINT_TEST) do
  source "Squint Test readability heuristic (Sandi Metz)"
  ask "Does this file have dense blocks with no visual breaks, or ragged indentation?"
  scope :file
  # Comment lines are content for this law, not noise. considered_text replaces
  # each one with a bare newline, so any four consecutive comment lines became
  # `\n\n\n\n` and read as a gap — which made every heavily-commented file in
  # this tree, including every file under law/, a finding about blank lines it
  # does not have.
  reads_comments true
  detect { |text| text.match?(/\n{4,}/m) }
  fix "One blank line between sections, never more than two consecutive."
  bad <<~'X'
    a



    b
  X
  good <<~'X'
    a

    b
  X
end
