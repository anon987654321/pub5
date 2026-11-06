# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:473 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9661d5b7214355a5
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:ERB_HARDCODED_CHROME) do
          tags %i[DESIGN I18N RAILS VIEWS]
          fix "empty/search chrome uses t() not hardcoded English (default_locale nb)"
          bad %(<%= render "shared/empty", title: "No results" %>\n)
          good %(<%= render "shared/empty", title: t("empty.results") %>\n)
          check do |src, path|
            next [] unless path.to_s.include?("/app/views/") && path.to_s.end_with?(".erb")
            next [] if path.to_s.end_with?("shared/_empty_state.html.erb")

            findings = []
            src.each_line.with_index(1) do |line, num|
              next if line.include?("t(") || line.include?("I18n.t") || line.include?("chrome_i18n: ok")
              next if line.lstrip.start_with?("<%#", "#")

              if line.match?(/title:\s*["'](?:No\s|Nothing\s)/) ||
                 line.match?(/placeholder:\s*["']Search/)
                findings << finding(
                  line: num,
                  message: "hardcoded EN chrome - use t(\"empty.*\") / t(\"search.*\") " \
                           "(design_rules.ui_polish.chrome_i18n; RAILS chrome_i18n_lint)",
                )
              end
            end

            findings
          end
        end
      end
    end
  end
end
