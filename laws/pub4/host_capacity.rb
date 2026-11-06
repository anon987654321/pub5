# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:664 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a03f318dcaffc06a
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:HOST_CAPACITY) do
          tags %i[OPS]
          fix "carrying capacity - avoid full-repo scan/fix in hot paths"
          example_path "/repo/lib/example.rb"
          bad "scanner.scan_dir(Master::ROOT)\n"
          good "scanner.scan_dir(target_dir)\n"
          check do |src, path|
            next [] unless path.to_s.include?("lib/")

            scan_lines(src, /scan_dir\([^)]*ROOT|fix_loop\.run\(\s*(@root|root|Master::ROOT)/,
              message: "full-root scan/fix - scope to path; respect host carrying capacity")
          end
        end
      end
    end
  end
end
