# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/naming.rb:175 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 370bd82313c3292a
require_relative "master/law/naming"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FILE_SEQUENCE_NAME) do
          tags %i[LOAD_BEARING_NAMES DOMAIN_LANGUAGE]
          fix "a filename records what a thing is, never where it sat in a sequence"
          reads_beyond_file true
          # A path rule that reads its siblings on disk; its test builds them.
          proved_by "test/laws/imported_pub4_proofs_test.rb"
          check do |_src, path|
              stem = File.basename(path.to_s, ".*")
              # db/migrate is timestamp-keyed by Rails and versioned API dirs are
              # a public contract; neither is a name someone chose loosely.
              next [] if path.to_s.match?(%r{/(?:db/migrate|node_modules|vendor)/|/v\d+/})

              # The sibling requirement, borrowed from NUMBERED_NAME above, is what
              # makes this measurable rather than noisy. Without it: 5 findings,
              # all false — upgrade_to_v1_10_generator.rb and
              # new_framework_defaults_8_0.rb are Rails names where the version IS
              # the subject, and backup.rb is a plain noun. A sequence word only
              # lies when a sibling shares the stem and carries a different one.
              hit = stem[/_((?:final|latest|new|old|copy|bak|tmp|temp)\d*|v?\d+)\z/, 1]
              next [] unless hit

              base = stem.sub(/_#{Regexp.escape(hit)}\z/, "")
              siblings = Dir.glob(File.join(File.dirname(path.to_s), "#{base}*.rb")).map { |f| File.basename(f, ".*") }
              next [] if siblings.size < 2

              [finding(line: 1, message: "FILE_SEQUENCE_NAME: #{File.basename(path)} - " \
                                         "'#{hit}' says when, not what; name the difference")]
          end
        end
      end
    end
  end
end
