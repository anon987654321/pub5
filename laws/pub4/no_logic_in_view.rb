# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:803 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a6240cf8d5904dbb
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_LOGIC_IN_VIEW) do
          tags %i[RAILS VIEWS]
          fix "views present; models/helpers compute"
          bad %(<% @posts.select { |p| p.published? }.each do |post| %>\n)
          good %(<%= render @posts %>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
            findings = []

            src.each_line.with_index(1) do |line, num|
              next unless line.include?("<%")
              # Only the Ruby inside a non-output tag: `<%#` comments and the page text
              # after `%>` named "where" or "find" in prose and read as a query.
              code = line.scan(/<%-?(?![=#])(.*?)(?:-?%>|\z)/m).flatten.join(" ")
              if code.match?(/\b(?:each|map|select|where|find|create|update|destroy|save!)\b/)
                findings << finding(line: num, message: "business/query logic in view - move to model/helper/component")
              end
            end
            findings
          end
        end
      end
    end
  end
end
