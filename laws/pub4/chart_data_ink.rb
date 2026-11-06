# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:525 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ed846e3594721cb0
require_relative "master/law/javascript"

module Law
  ::Law.define(:CHART_DATA_INK) do
    source "Tufte, The Visual Display of Quantitative Information (1983/2001): data-ink, chartjunk, lie factor"
    tags %i[DESIGN]
    path Regexp.union(/\.js\z/, S::SNAP::SNAPSHOT)
    fix "Start bars at zero, drop 3D and heavy gridlines, label the data directly, share one scale across multiples."
    bad "new Chart(el, { type: \"bar\", options: { scales: { y: { beginAtZero: false } } } })\n"
    good "new Chart(el, { type: \"bar\", options: { scales: { y: { beginAtZero: true } } } })\n"
    check do |src, _path|
      next [] unless src.match?(/\bnew Chart\(|\bChart\.register\b/)

      src.each_line.with_index(1).filter_map { |line, n| (message = S.chart_fault(line)) && finding(line: n, message:) }
    end
    tilted = S::SNAP.element("svg.chart", text: "", transform: "matrix3d(#{([1, 0, 0, 0, 0] * 3).push(1).join(", ")})")
    flat = S::SNAP.element("svg.chart", text: "", transform: "none", perspective: "none")
    adapter(:rendered_ui, languages: %i[json], example_path: S::SNAP::EXAMPLE, bad: S::SNAP.fixture(elements: [tilted]),
                          good: S::SNAP.fixture(elements: [flat]), &S.rendered(:CHART_DATA_INK))
  end
end
