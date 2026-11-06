# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:120 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e08c8aff2557bacf
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:RUBY_TERNARY_NOT_NESTED) do
          tags %i[STYLE]
          fix "no nested ternaries"
          bad "value = a ? (b ? 1 : 2) : 3\n"
          good "value = a ? 1 : 2\n"
          check do |src, path|
            result = Prism.parse(src)
            next [] if result.failure?

            findings = []
            walk = lambda do |node|
              return unless node
              if node.is_a?(Prism::IfNode) && node.if_keyword.nil? && Laws.nested_ternary_branch?(node)
                findings << finding(line: node.location.start_line,
                  message: "nested ternary - expand to if/elsif/else or case")
              end

              node.child_nodes.compact.each { |child| walk.call(child) }
            end
            walk.call(result.value)
            findings.uniq { |f| f[:line] }
          end
        end
      end
    end
  end
end
