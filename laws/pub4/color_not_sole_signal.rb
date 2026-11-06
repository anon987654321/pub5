# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:187 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6cf871a34c33b8cc
require_relative "master/law/rendered"

module Law
  Law.define(:COLOR_NOT_SOLE_SIGNAL) do
    online = { "data-state" => "online" }
    F.rendered(self, :COLOR_NOT_SOLE_SIGNAL,
               source: "WCAG 1.4.1 Use of Color; Albers, Interaction of Color (1963)",
               fix: "Carry each state in words, shape or weight as well as colour; tie an invalid field to text.",
               bad: F.page(F.el("span.dot", pid: 1, attrs: online, color: [0, 160, 0, 1]), F.el("span.dot", pid: 1)),
               good: F.page(F.el("span.dot", pid: 1, attrs: online, text: "Online"),
                            F.el("span.dot", pid: 1, text: "Ute")))
  end
end
