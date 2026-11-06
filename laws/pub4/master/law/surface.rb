# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c447c21744b868d9
require_relative "../lib/master"

require "prism"

module Master
  module Review
    module Scan
      module Laws
        # Surface law: pixel/UI aesthetic + Rails HTML/JS/ERB conventions.
        # One file — views, CSS, Stimulus, touch targets, flat design.

        # Pixel-perfect UI/UX rules restored from master.yml aesthetics + design_laws.yml.
        # Applies to MASTER/web face, ERB views, and pub4/RAILS SCSS/HTML.

        UI_PATH = %r{(?:/app/views/|/app/assets/|/web/public/|/web/app/|face\.|/RAILS/)}i.freeze
        CSS_LANGS = %i[css scss].freeze
        HTML_LANGS = %i[html].freeze

        module_function

        def ui_path?(path)
          path.to_s.match?(UI_PATH) || path.to_s.include?("views") || path.to_s.end_with?(".erb", ".html", ".scss", ".css")
        end

        def thresholds
          Master::Design::Thresholds
        end
        
        # The design scale's rules over tokens.yml#scale, shared with ScaleLint and
        # AstFixer#snap_to_design_scale. Read once per process.
        def design_scale
          @design_scale ||= Master::Design::Scale.new(Master.tokens.fetch("scale"))
        end

        # STIMULUS_CONTROLLER_SIZE's numbers are declared, not invented here:
        # data/laws.yml carries `detect_structural: {max_lines: 200,
        # path_pattern: "_controller\.js$"}` and this rule held both as literals,
        # which is a declaration with no reader — the defect this repo hunts most
        # often, sitting inside the file that declares the hunt. Read once per
        # process: laws.yml is four thousand lines and load_laws memoizes
        # nothing.
        def stimulus_limits
          @stimulus_limits ||= begin
            entry = Master.law_entries(root: Master::ROOT)
                          .find { |r| r["id"].to_s.upcase == "STIMULUS_CONTROLLER_SIZE" }

            config = entry && entry["detect_structural"]
            config.is_a?(Hash) ? config : {}
          end
        end

        



































        














































        # The doctrine is Müller-Brockmann's (Grid Systems in Graphic Design,
        # 1981): a single spatial module, every dimension a multiple of it —
        # named here so the rule carries its book, not just its number.
        # Grid structure is a composition law, not a requirement that every page use CSS Grid.
        # The static pass catches only a high-signal anti-pattern; it leaves unusual
        # but legitimate overlays to the semantic review and rendered geometry checks.
        

































        # One scale for the ratchet, this Law and its repair: Master::Design::Scale
        # reads tokens.yml#scale.space_px. This allowed any multiple of 4 up to 96
        # beside the declared steps, so 52px passed here and failed ScaleLint, and the
        # 8px snap that repaired it turned the scale's own 1px hairline into 0px.
        












































        




































        








































        





























































        

























        




















        

















        





























        












        # Family polish (design_rules ui_polish) — ERB chrome must be i18n; titles use tokens.
        



























        
























        












        


















        




























        
















        # One rule per trait, so one worked example per trait. They are declared
        # here rather than inline because the five rules share a body and differ
        # only in the branch each takes, which is exactly what the examples must
        # pin: a shared body is where a change to one trait silently becomes a
        # change to five.
        RAMS_FIXTURES = {
          "USEFUL" => [%(<p>Coming soon</p>\n), %(<p>Bergen i kveld</p>\n)],
          "UNDERSTANDABLE" => [%(<input placeholder="Q">\n), %(<input placeholder="Søk i byen">\n)],
          "UNOBTRUSIVE" => [%(<div class="modal">...</div>\n),
                            # The compliant spelling of the thing it checks: a
                            # dialog that announces itself correctly.
                            %(<dialog aria-modal="true">...</dialog>\n)],
          "HONEST" => [%(<div class="bar">loading 100%</div>\n), %(<div class="bar">42%</div>\n)],
          "THOROUGH" => [%(<form action="/search"><input name="q"></form>\n),
                         %(<form action="/search"><input name="q"><span class="error"></span></form>\n)],
        }.freeze

        










































        













        # Rails app surface.

        # Rails app law restored from master.yml rails_conventions — lexical/structural.
        # Applies under RAILS/, MASTER/web app views, and any app/ tree.

        RAILSISH = %r{(?:/RAILS/|/app/(?:controllers|models|helpers|views|javascript|assets)/)}i.freeze

        module_function

        def rails_path?(path)
          path.to_s.match?(RAILSISH)
        end

        # One past the line index of the `end` closing the `def` on line `start`.
        # Prism reads the method's own span: counting keywords took every modifier
        # `if`/`unless`, endless `def x = ...` and keyword in a string as an opener
        # with no `end`, so a 17-line action measured as ~100 and ran to the file's end.
        def method_body_end_line(lines, start)
          def_end_lines(lines.join)[start + 1] || lines.size
        end

        # { def start line => end line } (1-based) for every method in the source.
        def def_end_lines(src)
          ends = {}
          queue = [Prism.parse(src).value]
          while (node = queue.shift)
            ends[node.location.start_line] = node.location.end_line if node.is_a?(Prism::DefNode)
            queue.concat(node.compact_child_nodes)
          end
          ends
        end

        





































        















        # RAILS_TAG_HELPER lives once, as PREFER_TAG_HELPERS in law/web.rb: both fired on
        # one <tag><%= %></tag>, 1,029 and 978 findings over RAILS (2026-10-30 twin
        # retirement). Its exemption for t() was dropped: that is PREFER's own bad example.

        




















        













        





















        













        





















        
















      end
    end
  end
end
