# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:614 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: bf596539c2f4ae67
require_relative "master/law/html"

module Law
  ::Law.define(:ICON_CARRIES_WORD) do
    source "Norman, signifiers; Krug; minimalism.yml law.icon_policy, words before icons"
    tags %i[ACCESSIBILITY DESIGN]
    path M::VIEWS
    fix "Give the icon its word (\"Fremhev\") or use the word alone; minimalism.yml icon_words_optional may go bare."
    bad "<button class=\"boost\"><svg viewBox=\"0 0 9 9\"><path d=\"M0 0h9\"/></svg></button>\n"
    good "<button class=\"boost\"><svg viewBox=\"0 0 9 9\"><path d=\"M0 0h9\"/></svg> Fremhev</button>\n"
    check do |src, _path|
      src.each_line.with_index(1).filter_map do |line, n|
        tag = line.match(%r{<(button|a)\b([^>]*)>(.*?)</\1>}) or next
        finding(line: n, message: "icon-only #{tag[1]} with no word") if M.icon_only?(tag[3]) && !M.icon_named?(tag[2])
      end
    end
    adapter(:rendered_ui, languages: %i[json], example_path: M::SNAP::EXAMPLE,
                          bad: M.page(M.control("button.boost", icon: true, visible_text: "", name: "Boost")),
                          good: M.page(M.control("button.boost", icon: true, visible_text: "Fremhev", name: "Fremhev")),
                          &M.rendered(:ICON_CARRIES_WORD))
  end
end
