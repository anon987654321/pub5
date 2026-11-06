# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:364 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a38619fb26a8e6a6
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:PROGRESSIVE_DISCLOSURE) do
          source "Progressive disclosure (Jakob Nielsen, NN/g)"
          ask "Does this present all complexity at once instead of revealing detail as the user's task requires it?"
          tags %i[DESIGN UX]
          fix "Lead with the common path and reveal advanced controls when they become relevant."
          example_path "/repo/app/views/settings/edit.html.erb"
          bad %(<form class="settings">\n<input name=\"f1\">\n<input name=\"f2\">\n<input name=\"f3\">\n<input name=\"f4\">\n<input name=\"f5\">\n<input name=\"f6\">\n</form>\n)
          good %(<form class="settings">\n<details><summary>Advanced</summary>\n<input name=\"f1\">\n<input name=\"f2\">\n<input name=\"f3\">\n<input name=\"f4\">\n<input name=\"f5\">\n<input name=\"f6\">\n</details>\n</form>\n)
          check do |src, path|
            next [] unless %w[html].include?(language(path))
            next [] unless path.to_s.include?("/app/views/") || path.to_s.include?("web/")

            # "Dumping all options at once" needs options to dump. This fired on any
            # view containing the word settings/options/advanced anywhere — a link
            # label, a translation key, a URL — so a community's edit page and a
            # playlist embed page were reported as settings UI without a disclosure
            # pattern. The structural signal is a form with enough controls to be
            # worth collapsing; below that there is nothing to progressively reveal.
            next [] unless src.match?(/advanced|settings|options|preferences/i)
            next [] unless src.scan(/<(?:input|select|textarea)\b|f\.(?:text_field|select|check_box|number_field|text_area)/i).size >= 6
            next [] if src.match?(/details|disclosure|collapsed|hidden|aria-expanded|data-controller=["'][^"']*disclosure/i)

            [finding(line: 1, message: "settings/advanced UI without disclosure pattern - collapse secondary controls")]
          end
        end
      end
    end
  end
end
