# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:723 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3f56c197147fdb7a
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PLUCK_OVER_MAP) do
          tags %i[PERFORMANCE]
          fix "prefer pluck over map for single columns"
          example_path "/repo/RAILS/brgen/app/models/example.rb"
          bad "  ids = order.items.map(&:id)\n"
          good "  ids = order.items.pluck(:id)\n"
          check do |src, path|
            # pluck is ActiveRecord's; a plain Ruby array has no columns. The
            # guard was any /app/, /spec/ or /test/ path, so STUDIO's tool tests
            # were told to pluck from arrays.
            next [] unless path.match?(%r{(?:\A|/)RAILS/.*/(?:app|spec|test)/})
            scan_lines(src, /\.\w+\.map\(&:\w+\)/, message: "use pluck(:column) to avoid loading full objects")
          end
        end
      end
    end
  end
end
