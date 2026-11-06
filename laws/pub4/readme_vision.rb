# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:9 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 95325d22b26a8bfe
require_relative "master/law/recovered_design_semantics"

Law.define(:README_VISION) do
  path "MASTER/README.md"
  source "pub3 master.json documentation.readme_structure.vision - project vision leads README"
  scope :file
  detect do |text|
    paragraph = text.split(/\n\s*\n/).find do |block|
      line = block.strip
      !line.empty? && !line.start_with?("#")
    end.to_s.gsub(/\s+/, " ").strip
    sentences = paragraph.to_s.scan(/[^.!?]+[.!?](?=\s|\z)/).length
    paragraph.to_s.empty? || sentences > 3
  end
  fix "Put a concise 1-3 sentence project vision in the README's first prose paragraph."
  bad <<~X
    # pub4

    Setup details first.
    Run the command below.
    Then read the architecture.
    Finally you will discover what the project is for.
  X
  good <<~X
    # pub4

    MASTER governs the repository as an OpenBSD-like, self-cleaning system. It
    preserves working behavior while continuously reducing unnecessary
    complexity.
  X
end
