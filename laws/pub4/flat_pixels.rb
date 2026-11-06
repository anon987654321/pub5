# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:88 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a05b6adc2711d030
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:FLAT_PIXELS) do
          # One Law at two depths: the practice is the design principle, which binds
          # what gets built before there is a line to detect; the check is its lexical
          # detector for imageSmoothingEnabled and bloom/scanline language in a canvas
          # layer. They were two declarations in two files until the Law systems merged.
          source "MASTER constitution (soul.yml absolute.rules)"
          practice <<~TEXT
            Flat Design - UI and particles stay two-dimensional, uniform in size and
            alpha, with no fake depth or parallax. Exception: pixels that collectively
            resemble a 3D model, as in face mode.
          TEXT
          tags %i[DESIGN AESTHETIC PIXEL]
          fix "Keep the surface flat: uniform size and alpha, no fake depth or parallax."
          ask "Is the rendering intent 'crisp' or 'pixel-art', yet smoothing is enabled?"
          # Structural question: Check for 'smoothing' or 'blur' in JS filename/path
          example_path "/repo/web/public/face_vision.js"
          bad "ctx.imageSmoothingEnabled = true;\n"
          good "ctx.imageSmoothingEnabled = false;\n"
          check do |src, path|
            next [] unless %w[css scss javascript].include?(language(path))
            findings = []

            if path.to_s.match?(/\.(js|ts)\z/) || File.basename(path.to_s).match?(/face/)
              src.each_line.with_index(1) do |line, num|
                if line.match?(/imageSmoothingEnabled\s*=\s*true/i)
                  findings << finding(line: num, message: "imageSmoothingEnabled=true - pixel field requires false (integer scale)")
                end

                # `particle` is out of this list. bloom, scanline, vaporwave and crt
                # name decorative effects a flat surface does not want; a particle
                # is a rendering primitive, and this product's face is built from
                # them — face_vision_b.js opens "MASTER particle face 2026" and
                # face.part1.txt says it eight times. The rule was telling MASTER's
                # own particle face to stop calling itself one, and objecting to the
                # physics of a named feature (radio_brgen_tunnel's particle tunnel)
                # as though `particle.z += zDelta` were a style choice. 35 findings,
                # none actionable.
                if line.match?(/\b(bloom|scanline|vaporwave|crt)\b/i) && !line.strip.start_with?("//", "*", "/*")
                  findings << finding(line: num, message: "decorative particle/CRT language - use pixel-field/semantic cell terms per design_rules")
                end
              end
            end

            findings
          end
        end
      end
    end
  end
end
