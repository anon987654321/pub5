# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:826 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 2cd3a220e656d4c0
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:TRAILING_COMMAS) do
          source "Ruby/JS style - trailing commas in multiline literals"
          ask "Does a multiline collection or argument list omit a trailing comma that stabilizes diffs?"
          tags %i[STYLE]
          fix "Add the trailing comma to multiline collections and argument lists."
          bad %(LIST = [\n  "one"\n]\n)
          good %(LIST = [\n  "one",\n]\n)
          check do |src, path|
            next [] unless %w[ruby].include?(language(path))
            next [] if Master::Fix::Scan::AstFixer::DeadCodeAndCommas.rubocop_forbids_trailing_comma?(path)

            parsed = Prism.parse(src)
            next [] if parsed.failure?

            collections = each_node(parsed.value, Prism::ArrayNode) + each_node(parsed.value, Prism::HashNode)
            collections.filter_map do |node|
              next unless RubyRuleSupport.unterminated_collection?(node, src)

              finding(line: node.closing_loc.start_line, message: "missing trailing comma in multi-line collection")
            end
          end
        end
      end
    end
  end
end
