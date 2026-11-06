# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:622 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 350b3ad94d8ad767
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
%w[USEFUL UNDERSTANDABLE UNOBTRUSIVE HONEST THOROUGH].values_at(3).each do |trait|
          ::Law.define(:"RAMS_#{trait}") do
            tags %i[DESIGN RAMS]
            fix "Rams checklist tag: #{trait.downcase}"
            bad RAMS_FIXTURES.fetch(trait)[0]
            good RAMS_FIXTURES.fetch(trait)[1]
            check do |src, path|
              next [] unless ::Master::Review::Scan::Laws.ui_path?(path)
              next [] unless path.to_s.include?("/app/views/") || path.to_s.include?("web/")

              # Soft detectors — high-signal anti-patterns only
              case trait
              when "HONEST"
                scan_lines(src, /loading.*?100%|progress.*?100%|fake[-_ ]progress/i,
                  message: "possible dishonest progress UI - state must match system (Rams honest)")
              when "THOROUGH"
                next [] unless src.match?(/<form\b/i)
                next [] if src.match?(/error|invalid|aria-invalid|field_with_errors|empty|blank/i)
                [finding(line: 1, message: "form without visible error/empty handling - Rams thorough")]
              when "UNOBTRUSIVE"
                # ERB blanked, and aria-modal exempt. This word-matched raw lines,
                # so it fired on `aria-modal="true"` — the attribute that makes a
                # dialog announce itself correctly, i.e. the compliant spelling of
                # the thing it is checking — and on ERB comments that merely say
                # "showModal()". Neither is attention-capturing chrome. What is left
                # is markup that actually builds an overlay, which is the soft
                # signal this was written to give.
                scan_lines(without_erb_tags(src).gsub(/aria-modal\s*=\s*"[^"]*"/, ""),
                           /modal|overlay|popup|interstitial/i,
                  message: "attention-capturing chrome - keep unobtrusive unless blocking is required")
              when "UNDERSTANDABLE"
                scan_lines(src, /placeholder=["'][^"']{1,3}["']/,
                  message: "cryptic placeholder - labels must explain without folklore")
              when "USEFUL"
                scan_lines(src, /coming soon|lorem ipsum|placeholder content/i,
                  message: "non-useful placeholder content in shipped view")
              else
                []
              end
            end
          end
end
      end
    end
  end
end
