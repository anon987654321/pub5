# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:94 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bae54c9e9340cbe8
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:NO_DEBUG) do
    tags %i[CLEAN_CODE]
    fix "no debug breakpoints in committed code"
    bad "  binding.pry\n"
    good "debugger_enabled = false\n"
    check do |src, path|
      parsed = Prism.parse(src)
      next [] if parsed.failure?

      findings = []
      walk(parsed.value) do |node|
        if node.is_a?(Prism::CallNode) && node.name.to_s.match?(/^(pry|debugger|byebug|irb)$/)
          findings << finding(line: node.location.start_line, message: "debug breakpoint: #{node.name}")
        end
      end
      findings
    end
  end
      end
    end
  end
end
