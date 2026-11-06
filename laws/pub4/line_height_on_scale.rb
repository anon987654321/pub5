# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:224 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 4547f2918e1e1989
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:LINE_HEIGHT_ON_SCALE) do
          tags %i[DESIGN TYPOGRAPHY RHYTHM]
          fix "unitless line-height must be on the declared scale (tokens.yml scale.line_height)"
          transform "snap_to_design_scale"
          example_path "/repo/app/assets/stylesheets/_example.scss"
          bad ".prose { line-height: 1.45; }\n"
          good ".prose { line-height: 1.5; }\n.h1 { line-height: 1.25; }\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)
        
            scale = ::Master::Review::Scan::Laws.design_scale
            rules = ::Master::Design::Scale
            steps = scale.line_heights.map { |step| step == step.to_i ? step.to_i : step }.join("/")
            raw = src.lines
            findings = []
            without_block_comments(src).each_line.with_index(1) do |line, num|
              next if line.strip.start_with?("//")
              next if line.include?(rules::OPT_OUT) || (num > 1 && raw[num - 2].to_s.include?(rules::OPT_OUT))
        
              line.scan(rules::DECLARATION) do
                next unless Regexp.last_match[:prop] == "line-height"
        
                value = Regexp.last_match[:value].strip
                case scale.line_height_kind(value)
                when :absolute
                  findings << finding(line: num, message: "absolute line-height #{value} - prefer a unitless step #{steps} " \
                                                          "(tokens.yml scale.line_height; ScaleLint absolute_line_height)")
                when :off_scale
                  findings << finding(line: num, message: "line-height #{value} off scale - use #{steps} " \
                                                          "(tokens.yml scale.line_height; RAILS ScaleLint)")
                end
              end
            end
            findings.uniq { |f| [f[:line], f[:message]] }
          end
        end
      end
    end
  end
end
