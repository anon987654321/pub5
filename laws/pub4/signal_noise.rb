# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:539 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 725001b44445a5ea
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:SIGNAL_NOISE) do
          tags %i[DESIGN AESTHETIC]
          fix "too many competing visual classes on one node"
          bad %(<div class="card card--wide is-open u-mt-2 u-p-1 shadow rounded muted">x</div>\n)
          good %(<div class="card card--wide is-open">x</div>\n)
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            src.each_line.with_index(1).filter_map do |line, num|
              m = line.match(/class=["']([^"']+)["']/)
              next unless m
              classes = m[1].split(/\s+/)
              next if classes.size < 8

              finding(line: num, message: "#{classes.size} classes on one node - signal/noise; move layout to SCSS")
            end
          end
        end
      end
    end
  end
end
