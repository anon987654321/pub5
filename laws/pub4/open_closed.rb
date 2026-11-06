# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/structural.rb:707 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 733f2291ee202cd1
require_relative "master/law/structural"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:OPEN_CLOSED) do
          detector OpenClosedLaw
          tags %i[SOLID OCP]
          source "Open-Closed Principle (Bertrand Meyer; SOLID)"
          ask "Must existing core code be modified whenever a new supported variant is added?"
          fix "Extend through stable interfaces, registries, or composition where that reduces repeated core edits."
          bad <<~'X'
          case format; when :json; render_json; when :xml; render_xml; end
          X
          good <<~'X'
          renderers.fetch(format).call(document)
          X
          proved_by "test/test_solid_laws.rb"
        end
      end
    end
  end
end
