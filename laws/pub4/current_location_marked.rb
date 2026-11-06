# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:175 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 06ec3717e6547ec2
require_relative "master/law/rendered"

module Law
  Law.define(:CURRENT_LOCATION_MARKED) do
    here = { "path" => "/marked" }
    marked = { "aria-current" => "page" }
    home = F.el("a.home", in_nav: true, path: "/home")
    F.rendered(self, :CURRENT_LOCATION_MARKED,
               source: "Krug, Don't Make Me Think (2014): you-are-here indicators; Nielsen heuristic 1",
               fix: "Mark the current nav link with aria-current and a non-colour cue (weight, rule or shape).",
               bad: F.page(F.el("a.marked", in_nav: true, path: "/marked"), home, page: here),
               good: F.page(F.el("a.marked", in_nav: true, path: "/marked", font_weight: 700, attrs: marked), home,
                            page: here))
  end
end
