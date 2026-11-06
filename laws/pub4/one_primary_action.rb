# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:577 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 483548cb7eda8c22
require_relative "master/law/html"

module Law
  ::Law.define(:ONE_PRIMARY_ACTION) do
    source "Refactoring UI, button hierarchy; Von Restorff (Yablonski, Laws of UX); visual_identity.composition"
    tags %i[DESIGN UX]
    path M::VIEWS
    fix "Fill one action per view (button-primary); give the rest button-ghost or button-link."
    publish = M.erb("button_to \"Publiser\", posts_path, class: \"button-primary\"")
    bad publish + M.erb("link_to \"Del\", share_path, class: \"button-primary\"")
    good publish + M.erb("link_to \"Del\", share_path, class: \"button-ghost\"")
    check do |src, _path|
      hits = src.each_line.with_index(1).select { |line, _n| line.match?(/\bbutton-primary\b/) }
      message = "#{hits.size} primary actions in one view - one is primary"
      hits.drop(1).map { |_line, n| finding(line: n, message:) }
    end
    fill = [0, 80, 200, 1]
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE,
                          bad: M.page(M.control("button.a", bg: fill), M.control("button.b", bg: fill)),
                          good: M.page(M.control("button.a", bg: fill), M.control("button.b")),
                          &M.rendered(:ONE_PRIMARY_ACTION))
  end
end
