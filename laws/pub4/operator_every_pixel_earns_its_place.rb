# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_every_pixel_earns_its_place by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0a93920303c4e8ad
require_relative "master/lib/master"

Law.define(:OPERATOR_EVERY_PIXEL_EARNS_ITS_PLACE) do
  source "pub4 MASTER/data/project_context.yml operator_every_pixel_earns_its_place"
  practice "No unnecessary elements. Header, tab rail, mobile bottom bar and secondary\ncontrols hide while the reader reads and slide in on scroll-up or an edge\nswipe on touch, and on pointer movement toward an edge on desktop. They are\nalways shown at the page top, while a control inside has keyboard focus,\nwhen the page cannot scroll, and to assistive tech (hidden by transform,\nnever display:none on the reveal path); under prefers-reduced-motion they\nappear without sliding. Each page keeps its one primary action visible.\nSupersedes the always-visible bottom bar from the 2026-11-06 x.com review."
end
