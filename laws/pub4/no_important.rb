# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/web.rb:51 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ce0aae7119093d95
require_relative "master/law/web"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:NO_IMPORTANT) do
          tags %i[MAINTAINABILITY]
          fix "no !important"
          bad ".btn { background: #c00 !important; }\n"
          good ".btn { border: none !important; }\n"
          check do |src, path|
            # Not inside the media queries whose entire job is to override.
            #
            # `@media (prefers-reduced-motion: reduce) { * { animation: none
            # !important } }` is the recommended spelling, and it needs !important
            # precisely because it must beat whatever the author set — dropping it
            # would leave motion running for someone who asked the OS to stop it.
            # 73 of the 139 findings in this repo were that block, plus three in
            # prefers-contrast/forced-colors/print, which override for the same
            # reason. Telling an accessibility reset to "fix specificity instead" is
            # telling it to stop working.
            #
            # The same override exists class-shaped: _battery_aware.scss applies
            # .battery-low/.network-save-data from JS and must beat the author for
            # the same reason the media reset must. A file whose whole job is
            # overriding declares it with `scan: intentional-important` in its
            # head, the way a token source declares intentional-colors.
            next [] if src.lines.first(20).join.match?(/scan:\s*intentional-important/)
            #
            # An !important that ERASES chrome is a guarantee; one that PAINTS is
            # an argument. The flat system armours its wordmark, grips and
            # toggles with border/background/outline erased from anywhere —
            # converging styling to nothing cannot start the specificity war
            # this rule exists to prevent — so erase-shaped importants
            # (none/transparent/0) pass and painting ones still fire.
            erase = /(?:border|outline|background|padding|animation|transition|box-shadow|display)[\w-]*\s*:\s*(?:none|transparent|0)[^;!]*!\s*important/
            source_text = without_block_comments(without_override_media(src))
            # Markers are consulted on the ORIGINAL lines: the block-comment
            # stripping above blanks /* scan: intentional-marker */ before scan_lines
            # could see it.
            originals = src.lines
            source_text = source_text.each_line.with_index.map do |l, i|
              l.match?(erase) || l.lstrip.start_with?("//") || originals[i].to_s.match?(/scan:\s*intentional\b/) ? "\n" : l
            end.join
            scan_lines(source_text, /!\s*important/,
                       message: "!important overrides cascade - fix specificity instead")
          end
        end
      end
    end
  end
end
