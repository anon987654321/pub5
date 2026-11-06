# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:126 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 5441f32f93d2fd15
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ANTI_DIVITIS) do
          tags %i[DESIGN]
          fix "avoid styling-only wrappers and semantic div substitutes"
          bad %(<div class="header">\n)
          good %(<header class="header">\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            findings = scan_lines(src, /<div\s+class="(header|footer|nav|main|sidebar|article|section)"/i,
              message: "semantic landmark belongs on <header>/<nav>/<main>/<article>, not div.class")
            findings += scan_lines(src, /<div[^>]*>\s*<div[^>]*>\s*<div[^>]*>\s*<div/i,
              message: "div nesting depth > 3 - flatten or use semantic elements")
            findings
          end
        end
      end
    end
  end
end
