# frozen_string_literal: true

module Deploy
  module RenderedDesign
    # Near-duplicate colour: two inks one small OKLab distance apart read as one
    # colour and should be one token. The distance is house policy, not a
    # standard - laws.yml design_thresholds.oklch_merge_distance carries
    # it so tuning the level is an operator decision, not a code change.
    module ColourLaws
      module_function

      # sRGB to OKLab (Bjorn Ottosson's reference transform). Math.cbrt keeps
      # the cube root honest for the negative branch this tree's greys never
      # take but a saturated colour might.
      def oklab(rgb)
        linear = rgb.first(3).map do |value|
          channel = value.to_f / 255
          channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
        end
        l = Math.cbrt(0.4122214708 * linear[0] + 0.5363325363 * linear[1] + 0.0514459929 * linear[2])
        m = Math.cbrt(0.2119034982 * linear[0] + 0.6806995451 * linear[1] + 0.1073969566 * linear[2])
        s = Math.cbrt(0.0883024619 * linear[0] + 0.2817188376 * linear[1] + 0.6299787005 * linear[2])
        [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
         1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
         0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
      end

      def distance(one, two)
        Math.sqrt(oklab(one).zip(oklab(two)).sum { |a, b| (a - b)**2 })
      end

      def near_duplicates(view)
        limit = RenderedDesign.threshold("oklch_merge_distance", 0.02).to_f
        painted = RenderedDesign.texts(view).group_by { |element| Array(element["color"]).first(3) }
        painted.keys.combination(2).filter_map do |one, two|
          gap = distance(one, two)
          next unless gap < limit

          "warning: #{painted[one].first["key"]} and #{painted[two].first["key"]} are #{gap.round(3)} apart in " \
          "OKLab (< #{limit}); one token should carry both"
        end
      end
    end

    register(:COLOR_NEAR_DUPLICATE) { |snap| each_view(snap) { |view| ColourLaws.near_duplicates(view) } }
  end
end
