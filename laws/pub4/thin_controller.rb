# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:710 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c77f5647ee74f5ac
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:THIN_CONTROLLER) do
          tags %i[RAILS ARCHITECTURE]
          fix "thin controllers - business logic belongs in models/services"
          example_path "/repo/app/controllers/example_controller.rb"
          bad %(def index\n  @posts = Post.where("created_at > ? AND city_id = ? AND published = ?", a, b, c)\nend\n)
          good "def index\n  @posts = Post.recent\nend\n"
          check do |src, path|
            next [] unless path.to_s.include?("/controllers/")
            next [] unless path.to_s.end_with?(".rb")

            findings = []
            # fat action: many lines between def and end of public action methods
            lines = src.lines
            i = 0

            while i < lines.size
              if lines[i].match?(/^\s*def\s+\w+/)
                start = i
                j = ::Master::Review::Scan::Laws.method_body_end_line(lines, start)
                body_len = j - start
                if body_len > 40
                  findings << finding(line: start + 1, message: "controller action ~#{body_len} lines - thin controllers, fat models/services (rails_conventions)")
                end
                # SQL / business in controller
                chunk = lines[start...j].join
                if chunk.match?(/\b(?:ActiveRecord::Base\.connection|find_by_sql|\.where\([^)]{40,})/m)
                  findings << finding(line: start + 1, message: "query logic in controller - move to model/query object")
                end
                i = j
              else
                i += 1
              end
            end

            findings
          end
        end
      end
    end
  end
end
