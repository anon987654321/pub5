# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:792 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b8ce7acb80f26037
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ABC_SIZE) do
          tags %i[COMPLEXITY]
          fix "method ABC size over the ratchet threshold - extract until the pieces name themselves"
          example_path "/repo/lib/example.rb"
          bad "def dense(x)\n" + Array.new(20) { |i| "  v#{i} = x.call(#{i}) if x.ok?(#{i})\n" }.join + "end\n"
          good "def calm(x)\n  y = x.call\n  y ? y.to_s : nil\nend\n"
          check do |src, path|
            result = Prism.parse(src)
            next [] if result.failure?

            findings = []
            walk = lambda do |node|
              next unless node.respond_to?(:child_nodes)
              if node.is_a?(Prism::DefNode)
                a, b, c = RubyRuleSupport.abc_counts(node)
                abc = Math.sqrt(a**2 + b**2 + c**2)
                if abc > 40
                  findings << finding(line: node.location.start_line,
                    message: "ABC size #{abc.round(1)} for ##{node.name} (A=#{a} B=#{b} C=#{c}, ratchet 40) - extract until the pieces name themselves")
                end
              end
              node.child_nodes.compact.each { |child| walk.call(child) }
            end
            walk.call(result.value)
            findings
          end
        end
      end
    end
  end
end
