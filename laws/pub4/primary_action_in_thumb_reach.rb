# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rendered.rb:167 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: fac286ef707b099f
require_relative "master/law/rendered"

module Law
  Law.define(:PRIMARY_ACTION_IN_THUMB_REACH) do
    F.rendered(self, :PRIMARY_ACTION_IN_THUMB_REACH,
               source: "Josh Clark, Designing for Touch: the thumb zone; layout_rules.touch.thumb_zone_primary_actions",
               fix: "Place the primary action low and central on a phone: a bottom bar or the end of the form.",
               bad: F.page(F.el("button.order", primary: true, rect: { "x" => 300, "y" => 20, "w" => 70, "h" => 44 })),
               good: F.page(F.el("button.order", primary: true, rect: F.at(780).merge("h" => 44))))
  end
end
