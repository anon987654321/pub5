# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:700 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 47e75109ce749095
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FIND_EACH) do
          tags %i[PERFORMANCE]
          fix "use find_each for batch processing"
          bad "  User.all.each { |u| u.touch }\n"
          good "  User.find_each(batch_size: 500) { |u| u.touch }\n"
          check do |src, path|
            next [] unless path.match?(%r{/app/|/spec/|/test/})
            scan_lines(src, /\.(all\.each|where\(.*\)\.each)\b/,
              message: "unbounded .all.each - use find_each(batch_size: N)")
          end
        end
      end
    end
  end
end
