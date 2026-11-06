# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:597 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 323db073d60c194a
require_relative "master/law/html"

module Law
  ::Law.define(:LABEL_IN_NAME) do
    source "WCAG 2.5.3 Label in Name, A"
    tags %i[ACCESSIBILITY]
    path M::VIEWS
    fix "Make the accessible name contain the visible text: drop the aria-label, or extend the words shown."
    bad "<button aria-label=\"Send inn\">Lagre</button>\n"
    good "<button aria-label=\"Lagre annonse\">Lagre</button>\n"
    check do |src, _path|
      src.each_line.with_index(1).filter_map do |line, n|
        (message = M.name_mismatch(line)) && finding(line: n, message:)
      end
    end
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE,
                          bad: M.page(M.named("Send inn", "Lagre")), good: M.page(M.named("Lagre annonse", "Lagre")),
                          &M.rendered(:LABEL_IN_NAME))
  end
end
