# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws
        # DOCUMENT_* generalizes PRINT_PAGE_CANON and the BUSPLAN_* print pair
        # into executable print-canon checks for the BIZ documents: what every
        # paged professional document owes its reader regardless of the plan it
        # carries. The rules are lexical and qualitative on purpose. Numeric
        # thresholds (body size, leading, margins) wait for verified guidance
        # from the receiving institution; design_thresholds records a number
        # only after measuring, and an unverified one never becomes a Law.
        module DocumentRuleSupport
          PAGED_MEDIA = /@media\s+print|@page\s*\{/.freeze
          FOLIO_MARGIN_BOX = /@bottom-(?:left|center|right)[^{]*\{[^}]*counter\s*\(\s*pages?\s*\)/m.freeze

          module_function

          # The line that opens the paged stylesheet, so the finding lands
          # where the fix goes.
          def open_line(src, pattern)
            src.each_line.with_index(1).find { |line, _| line.match?(pattern) }&.last || 1
          end
        end

        ::Law.define(:DOCUMENT_FOLIO_IN_THE_FOOT) do
          path "BIZ/"
          example_path "/repo/BIZ/__templates/example.html"
          tags %i[DOCUMENT PRINT]
          fix "construct the folio in the page's own margin boxes: @bottom-center { content: counter(page) \" av \" counter(pages) }"
          bad "@page { margin: 1in; }\np { color: #111; }\n"
          good "@page {\n  margin: 1in;\n  @bottom-center { content: counter(page) \" av \" counter(pages); }\n}\n"
          check do |src, _path|
            next [] unless src.match?(/@page\s*\{/)

            next [] if src.match?(DocumentRuleSupport::FOLIO_MARGIN_BOX)

            [finding(line: DocumentRuleSupport.open_line(src, /@page\s*\{/),
                     message: "paged document carries no folio in the foot")]
          end
        end

        ::Law.define(:DOCUMENT_WIDOW_ORPHAN_CONTROL) do
          path "BIZ/"
          example_path "/repo/BIZ/__templates/example.html"
          tags %i[DOCUMENT PRINT]
          fix "set widows and orphans in the print stylesheet so a page never opens or ends on one stray line"
          bad "@media print {\n  p { margin: 0 0 1em; }\n}\n"
          good "@media print {\n  p { widows: 2; orphans: 2; }\n}\n"
          check do |src, _path|
            next [] unless src.match?(DocumentRuleSupport::PAGED_MEDIA)

            next [] if src.match?(/(?:widows|orphans)\s*:/)

            [finding(line: DocumentRuleSupport.open_line(src, DocumentRuleSupport::PAGED_MEDIA),
                     message: "paged document declares no widow or orphan control")]
          end
        end

        ::Law.define(:DOCUMENT_HEADING_STAYS_WITH_BODY) do
          path "BIZ/"
          example_path "/repo/BIZ/__templates/example.html"
          tags %i[DOCUMENT PRINT]
          fix "keep each heading with the block it names: break-after: avoid on the print heading"
          bad "@media print {\n  h2 { font-size: 1.5em; }\n}\n"
          good "@media print {\n  h2 { font-size: 1.5em; break-after: avoid; }\n}\n"
          check do |src, _path|
            next [] unless src.match?(DocumentRuleSupport::PAGED_MEDIA)

            next [] unless src.match?(/\bh[1-6]\b[^{}]*\{/m)

            next [] if src.match?(/(?:page-)?break-after\s*:\s*avoid/)

            [finding(line: DocumentRuleSupport.open_line(src, DocumentRuleSupport::PAGED_MEDIA),
                     message: "styled headings carry no break-after: avoid")]
          end
        end

        ::Law.define(:DOCUMENT_TABULAR_FIGURES) do
          path "BIZ/"
          example_path "/repo/BIZ/__templates/example.html"
          tags %i[DOCUMENT PRINT]
          fix "align numeric columns: font-variant-numeric: tabular-nums on the table"
          bad "table { border-collapse: collapse; }\n"
          good "table { border-collapse: collapse; font-variant-numeric: tabular-nums; }\n"
          check do |src, _path|
            table_rule = /(?:table|tbody|thead|tfoot|\btd\b|\bth\b)[^{,;]*\{/
            next [] unless src.match?(table_rule)

            next [] if src.match?(/font-variant-numeric\s*:\s*[^;]*tabular/)

            [finding(line: DocumentRuleSupport.open_line(src, table_rule),
                     message: "styled tables set no tabular figures")]
          end
        end
      end
    end
  end
end
