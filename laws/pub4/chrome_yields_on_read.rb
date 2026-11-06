# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:137 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d49f9c5bd0157e39
require_relative "master/law/rendered"

module Law
  Law.define(:CHROME_YIELDS_ON_READ) do
    F.rendered(self, :CHROME_YIELDS_ON_READ,
               source: "Operator directive operator_every_pixel_earns_its_place (2026-11-06); WCAG 2.4.11; Krug",
               fix: "Translate chrome out of view on scroll-down (transform, not display none) and bring it back " \
                    "on scroll-up, focus and at the top.",
               bad: F.page(**F.chrome(top: [F.bar("header", 0.05)],
                                      down: [F.bar("header", 0, on_screen: false, display: "none")])),
               good: F.page(**F.chrome(top: [F.bar("header", 0.05)], down: [F.bar("header", 0, on_screen: false)],
                                       up: [F.bar("header", 0.05)])))
  end
end
