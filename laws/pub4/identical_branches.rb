# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:298 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f22b979943cf0a54
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:IDENTICAL_BRANCHES) do
    tags %i[COMPLETENESS]
    fix "a conditional whose branches are identical"
    bad "def auth?(path) = PATHS.include?(path) ? false : false\n"
    good "def auth?(path) = PATHS.include?(path) ? false : true\n"
    check do |src, path|
      parsed = Prism.parse(src)

      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        taken, other = case node
                       when Prism::IfNode then [node.statements, node.subsequent]
                       when Prism::UnlessNode then [node.statements, node.else_clause]
                       end
        # An elsif chain is an IfNode here, not an ElseNode, and is left alone.
        body = other.statements if other.is_a?(Prism::ElseNode)
        same = body && taken&.slice&.strip == body&.slice&.strip
        next unless same

        findings << finding(line: node.location.start_line, message: "both branches are `#{body.slice.strip[0, 40]}`")
      end
      findings
    end
  end
      end
    end
  end
end
