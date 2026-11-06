# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1900 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3ebc2a7f3deac4a4
require_relative "master/law/universal"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:N_PLUS_ONE) do
          tags %i[PERFORMANCE]
          fix "loading records one-by-one inside a loop"
          example_path "/repo/RAILS/x/app/models/y.rb"
          bad "posts.each { |post| post.author.name }\n"
          good "posts.each { |post| post.title }\n"
          check do |src, path|
            # Only meaningful in Rails trees; non-AR enumerable chains are fine.
            next [] unless path.match?(%r{(?:\A|/)RAILS/.*/(?:app|spec|test)/})

            scan_lines(src, /\.(each|map|collect)\s*(do|\{).*\.\w+\.\w+/,
              message: "N+1 query candidate - use includes/eager_load")
          end
        end
      end
    end
  end
end
