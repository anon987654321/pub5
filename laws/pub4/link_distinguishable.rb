# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:197 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 8ed98fb652b17ca6
require_relative "master/law/rendered"

module Law
  Law.define(:LINK_DISTINGUISHABLE) do
    text = [51, 51, 51, 1]
    F.rendered(self, :LINK_DISTINGUISHABLE,
               source: "WCAG 1.4.1 (G183, F73); Butterick, underline is for links; Krug, obvious clickability",
               fix: "Underline links in running text (text-decoration-thickness 1px, underline-offset .15em).",
               bad: F.page(F.el("a", in_text: true, parent: "p", color: [59, 108, 196, 1], parent_color: text)),
               good: F.page(F.el("a", in_text: true, parent: "p", decoration: "underline", parent_color: text)))
  end
end
