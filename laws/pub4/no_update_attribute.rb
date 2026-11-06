# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:712 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 66f707afc102eaa4
require_relative "master/law/ruby"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_UPDATE_ATTRIBUTE) do
          tags %i[DATA_INTEGRITY]
          fix "replace update_attribute with update!"
          bad "  user.update_attribute(:name, name)\n"
          good "  user.update!(name: name)\n"
          check do |src, path|
            next [] unless path.match?(%r{/app/|/spec/|/test/})
            scan_lines(src, /\.update_attribute\(/, message: "update_attribute skips validations - use update!")
          end
        end
      end
    end
  end
end
