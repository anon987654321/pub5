# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:217 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 543d9263c2886ab8
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SINGLE_H1) do
          tags %i[SEO ACCESSIBILITY]
          fix "one h1 per view surface"
          bad %(<h1>Bergen</h1>\n<h1>Oslo</h1>\n)
          good %(<h1>Bergen</h1>\n<h2>Oslo</h2>\n)
          check do |src, path|
            next [] unless path.include?("/app/views/")
            # A locale-branched page renders one h1 per request while carrying
            # two in source; the marker names that shape.
            next [] if src.include?("single_h1: locale-branched")
            count = src.scan(/<h1\b/i).size
            next [] if count <= 1
            [finding(line: 1, message: "#{count} <h1> tags - keep one primary heading per view")]
          end
        end
      end
    end
  end
end
