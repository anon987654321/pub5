# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/surface.rb:302 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: e6a97b54fae85380
require_relative "master/law/surface"

module Master
  module Review
    module Scan
      module Laws
        ::Law.define(:CHOICE_OVERLOAD) do
          tags %i[DESIGN UX]
          fix "Hick - too many peer choices without grouping"
          bad "<nav>#{(1..8).map { |n| "<a href=\"/#{n}\">#{n}</a>" }.join}</nav>\n"
          good "<ul>#{(1..8).map { |n| "<li>#{n}</li>" }.join}</ul>\n"
          check do |src, path|
            next [] unless ::Master::Review::Scan::Laws.ui_path?(path)

            max = ::Master::Review::Scan::Laws.thresholds.max_visible_choices.to_i
            findings = []

            # count sibling <li> or nav links in a single block
            #
            # A bare <ul> is not a choice surface. Hick's law is about how long it
            # takes to decide between alternatives, and a tag cloud, a search-results
            # list and "what is on in the city today" are content being browsed, not
            # options being chosen between — advising "group or progressive
            # disclosure" on search results says to hide the results. <nav> and
            # <select> are choice surfaces by definition and still count; a <ul> only
            # counts when it says it is one.
            menu_ul = /<ul[^>]*(?:role=["']menu|class=["'][^"']*(?:menu|nav|tabs|filters))/i

            src.scan(/<(?:ul|nav|select)[^>]*>(.*?)<\/(?:ul|nav|select)>/im) do |body|
              chunk = body[0].to_s

              # From the character BEFORE the body, or rindex answers with the
              # body's own first `<`: a chunk that opens `<li>` made every plain
              # <ul> look like a <li> and skipped the exemption below, which is
              # the whole reason this rule reads the opening tag. Found by its own
              # worked example, 2026-09-06.
              start = src.index(chunk)

              opening = src[start ? (src.rindex("<", [start - 1, 0].max) || 0) : 0, 200].to_s
              next if opening.start_with?("<ul") && !opening.match?(menu_ul)
              count = chunk.scan(/<li\b/i).size
              count = chunk.scan(/<option\b/i).size if count.zero?
              count = chunk.scan(/<a\b/i).size if count.zero?
              line = src[0, src.index(chunk) || 0].count("\n") + 1

              if count > max
                findings << finding(line:, message: "#{count} peer choices > #{max} (Hick) - group or progressive disclosure")
                next
              end

              # A Rails `.each` loop renders exactly one static <a>/<li> in the
              # source text regardless of runtime item count — the literal
              # count above is structurally blind to the normal way Rails
              # renders a nav (found 2026-07-21: brgen's 10-item nav_swiper
              # was exactly this shape and this rule never saw it). Can't know
              # the real count statically, so this is advisory, not a hard
              # count — skip if the block already shows a grouping signal.
              next unless count <= 1 && chunk.match?(/<%[-=]?\s*[\w."'\[\]]+\.each(?:_with_index)?\s+do\s*\|/)

              next if chunk.match?(/role=["']group["']|data-controller=["'][^"']*(?:group|collapse|disclosure)/i)
              next if chunk.scan(/\.each(?:_with_index)?\s+do\s*\|/).size > 1 # already chunked into sub-groups

              findings << finding(line:, message: "dynamic choice list (.each loop, real count unknown statically) with no grouping signal - verify it can't exceed #{max} peers, or add role=\"group\"/progressive disclosure (Hick)")
            end
            findings
          end
        end
      end
    end
  end
end
