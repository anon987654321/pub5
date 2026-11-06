# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:558 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ad11aec0025b20ee
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:AFFORDANCE_CLARITY) do
          tags %i[DESIGN UX]
          fix "clickable non-buttons need clear affordance"
          bad %(<div data-action="click->dropdown#toggle">Menu</div>\n)
          good %(<div data-action="click@window->dropdown#hide">Menu</div>\n)
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            # An element is interactive when something activates it, not when a
            # Stimulus controller is attached to it. `data-controller` was in this
            # list and produced 79 of the 87 findings — `<div
            # data-controller="character-counter">` is a wrapper that watches a
            # textarea and prints a number, with no handler and nothing to press.
            # Advising a <button> there is advice nobody can take, and eleven
            # unusable findings per usable one is how a rule stops being read.
            #
            # data-action is kept but narrowed to element-scoped activation.
            # Stimulus writes the global form as `click@window->dropdown#hide`,
            # which is a click-outside listener on the *window* and says nothing
            # about the div carrying it; drag and scroll bindings are drop zones and
            # observers, which are correctly divs. Element-scoped click/keydown on a
            # bare div is the case this rule is actually about.
            activation = /onclick|data-action="[^"]*(?<!@window|@document)\b(?:click|keydown|keyup)->/i

            scan_lines(src, /<(div|span)[^>]*#{activation}[^>]*>/i,
              message: "interactive div/span - use <button> or explicit role+tabindex+keyboard handler")
          end
        end
      end
    end
  end
end
