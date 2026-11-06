# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/cosmetic.rb:174 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: f17d4e1f39cc7552
require_relative "master/law/cosmetic"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:DOUBLE_QUOTES_RUBY) do
          tags %i[STYLE]
          fix "double-quoted strings per style.yml"
          bad %(name = 'osman'\n)
          good %(name = "osman"\n)
          check do |src, path|
            parsed = Prism.parse(src)
            next [] if parsed.failure?

            exempt = each_node(parsed.value, Prism::CallNode)
              .select { |call| CosmeticRuleSupport::LITERAL_QUOTE_CALLS.include?(call.name.to_s) }
              .flat_map { |call| Array(call.arguments&.arguments) }
              .map { |argument| argument.location.start_offset }

            interpolations = each_node(parsed.value, Prism::EmbeddedStatementsNode)
              .map { |node| node.location.start_offset...node.location.end_offset }

            each_node(parsed.value, Prism::StringNode).filter_map do |node|
              next unless CosmeticRuleSupport.convertible_single_quote?(node)
              next if exempt.include?(node.location.start_offset)
              next if interpolations.any? { |span| span.cover?(node.location.start_offset) }

              finding(line: node.location.start_line, message: "single-quoted string - use double quotes per style.yml")
            end
          end
        end
      end
    end
  end
end
