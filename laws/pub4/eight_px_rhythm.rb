# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:179 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d3ced5eb3fa2e628
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:EIGHT_PX_RHYTHM) do
          tags %i[DESIGN AESTHETIC]
          fix "spacing on the declared scale (tokens.yml scale.space_px) - Müller-Brockmann grid module"
          ask "Does the spacing step off the declared scale rather than follow its rhythm?"
          transform "snap_to_design_scale"
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".card { padding: 10px; }\n"
          good "@media (min-width: 1280px) { .card { padding: 24px; min-height: 44px; } }\n.rule { margin: 1px 0; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)
        
            scale = ::Master::Review::Scan::Laws.design_scale
            rules = ::Master::Design::Scale
            raw = src.lines
            findings = []
            without_block_comments(src).each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//")
              next if line.include?(rules::OPT_OUT) || (num > 1 && raw[num - 2].to_s.include?(rules::OPT_OUT))
        
              line.scan(rules::DECLARATION) do
                prop = Regexp.last_match[:prop]
                next unless rules::SPACE_PROPS.include?(prop)
        
                scale.off_scale_lengths(Regexp.last_match[:value]).each do |step|
                  px = rules.to_px(*step.match(rules::LENGTH).captures)
                  findings << finding(line: num, message: "#{step} #{prop} off the spacing scale - " \
                                                          "use #{scale.nearest(px).to_i}px (tokens.yml scale.space_px)")
                end
              end
        
              # Token *definitions* (e.g. --space-7: 1.75rem), not just call sites — a
              # usage-only scan is structurally blind to a bad value baked into the
              # token itself. Reported, never snapped: a token's value is the operator's.
              line.scan(/--[\w-]*(?:space|gap)[\w-]*\s*:\s*(-?[\d.]+)(px|rem)\b/i) do |value, unit|
                px = rules.to_px(value, unit.downcase)
                next if px.zero? || scale.space_px.include?(px.abs.round(3))
        
                findings << finding(line: num, message: "#{px.to_i}px spacing token off the scale - " \
                                                        "use #{scale.nearest(px).to_i}px (tokens.yml scale.space_px)")
              end
            end
            findings.uniq { |f| [f[:line], f[:message]] }
          end
        end
      end
    end
  end
end
