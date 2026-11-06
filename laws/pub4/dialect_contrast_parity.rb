# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/brand.rb:159 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f2ef5b02a3517919
require_relative "master/law/brand"

module Law
  Law.define(:DIALECT_CONTRAST_PARITY) do
    source "Albers, Interaction of Color (1963); WCAG 1.4.3; operator 2026-11-06: 4.5:1 minimum, 7:1 for body text"
    tags %i[DESIGN ACCESSIBILITY]
    path %r{MASTER/data/tokens\.yml\z}
    example_path "/repo/MASTER/data/tokens.yml"
    fix "Bring the drifting role into the band in both modes: muted >= 4.5:1, text >= 7:1, borders within 35%."
    bad DialectContrast.fixture("#222222")
    good DialectContrast.fixture("#666666")
    check do |src, _path|
      DialectContrast.findings(src).map do |block, message|
        finding(line: (src.lines.index { |line| line.match?(/\A  #{Regexp.escape(block)}:/) } || 0) + 1, message:)
      end
    end
  end
end
