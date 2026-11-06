# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:266 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7808ea8e83bb5a18
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:RESCUE_EXCEPTION) do
    tags %i[ERROR_HANDLING]
    fix "rescue StandardError not Exception"
    bad "begin\nrescue Exception => e\nend\n"
    good "begin\n  # rescue Exception belongs to this rule\nrescue StandardError => e\nend\n"
    check do |src, path|
      # Comment lines blanked, not the directory skipped: a real `rescue
      # Exception` in a scanner rule is worth catching, and SILENT_RESCUE's note
      # below says why this population carries no path exemption.
      parsed = Prism.parse(src)

      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        next unless node.is_a?(Prism::RescueNode)

        # Prism::RescueNode#exceptions is the list of classes named on the
        # `rescue` line. A bare 'rescue' has none and defaults to StandardError.
        handled = node.exceptions
        next unless handled&.any? { |ex| ex.slice.to_s == "Exception" }

        findings << finding(line: node.location.start_line, message: "catches signals - use StandardError")
      end
      findings
    end
  end
      end
    end
  end
end
