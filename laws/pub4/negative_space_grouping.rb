# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/geometry.rb:86 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 96f3a21383fda48f
require_relative "master/law/geometry"

module Law
  ::Law.define(:NEGATIVE_SPACE_GROUPING) do
    GP.declare(self, :NEGATIVE_SPACE_GROUPING)
    path GP::G::SNAPSHOT
    source "Gestalt proximity (Lupton, Thinking with Type); Refactoring UI, more space between groups; Hara, White"
    fix "Make the space between groups larger than the space within; close any void taller than a third of the screen."
    bad GP.grouped(120)
    good GP.grouped(144)
  end
end
