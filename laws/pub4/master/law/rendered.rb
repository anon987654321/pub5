# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 3276e28976bdd584
require_relative "../lib/master"

# law/rendered.rb - the design-book Laws only a rendered page can answer, one Law.define per law.
#
# Each reads one snapshot that checks/support/geometry_probe/design_laws.js measured through
# CDP (computed styles, line boxes, chrome states, focus stops, text spacing, motion, bytes),
# at 390, 360 and 320 wide before the desktop. The judgement is Deploy::RenderedDesign's, so
# the fixtures below (snapshots) prove each Law at load, the rendered suite's DesignLawsCheck
# runs the same evaluator on every declared surface, and test/test_rendered_design_laws.rb
# renders a bad and a good HTML page per Law in headless Chrome. No Chrome is INCONCLUSIVE.
require_relative "../checks/support/rendered_design"

module Law
  # The rendered snapshot path and the fixture builders the Laws below share.
  module RenderedFixtures
    PATH = Regexp.union(Deploy::RenderedDesign::SNAPSHOT, /\.s?css\z/)
    EXAMPLE = Deploy::RenderedDesign::EXAMPLE
    SNAP = Deploy::RenderedDesign
    PHONE_AREA = 390 * 844
    BLACK = [0, 0, 0, 1].freeze

    module_function

    def page(*elements, **view) = SNAP.fixture(elements:, **view)
    def el(key, **fields) = SNAP.element(key, **fields)
    def snap(**top) = { "probe" => "design_laws", "viewports" => [] }.merge(top.transform_keys(&:to_s)).to_json
    def at(top) = { "x" => 16, "y" => top, "w" => 358, "h" => 24 }
    def sizes(*pixels)
      pixels.each_with_index.map { |size, row| el("p.s#{row}", font_size: size, rect: at(16 + (row * 40))) }
    end
    def scrolled = { "scroll_height" => 3000, "inner_height" => 844 }
    def chrome(**states) = { "chrome" => states.transform_keys(&:to_s), "page" => scrolled }

    def bar(key, share, on_screen: true, **more)
      row = { "key" => key, "area" => share * PHONE_AREA, "on_screen" => on_screen, "display" => "block" }
      row.merge(more.transform_keys(&:to_s))
    end

    def font(weight, face)
      painted = { "familyName" => "Arial", "postScriptName" => face, "glyphCount" => 5, "isCustomFont" => false }
      { "family" => "Arial", "weight" => weight, "style" => "normal", "caps" => "normal", "synthesis" => "weight style",
        "platform" => [painted] }
    end

    def strobe(step) = { "key" => "canvas.strobe", "samples" => (0..20).map { |i| [i * step, i.even? ? 0.0 : 0.9] } }

    def edge(key, left) = el(key, in_main: true, display: "block", content_x: left)

    def input(border)
      el("input", attrs: { "type" => "text" }, border_width: 1, border_color: border, bg: [17, 17, 17, 1],
                  ground: BLACK)
    end

    def card(width, border) = el("div.card", text: "", border_width: width, border_color: border, ground: BLACK)

    def checker(id) = ->(text, file) { SNAP.findings(id, text, file).map { |hit| finding(**hit) } }

    # The parts every rendered Law shares, declared on its Law.define builder.
    def rendered(law, law_id, **said)
      law.instance_exec(law_id, said) do |id, words|
        source words.fetch(:source)
        tags %i[DESIGN UX]
        measures :rendered_ui
        path PATH
        example_path EXAMPLE
        fix words.fetch(:fix)
        bad words.fetch(:bad)
        good words.fetch(:good)
        check(&RenderedFixtures.checker(id))
      end
    end
  end

  F = RenderedFixtures

  







  








  

















  








  







  








  










  


















  







  











  









  








  






  






  








  







  







  








  










end
