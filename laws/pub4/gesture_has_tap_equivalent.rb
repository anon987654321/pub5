# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/javascript.rb:490 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0cba55a08008d197
require_relative "master/law/javascript"

module Law
  ::Law.define(:GESTURE_HAS_TAP_EQUIVALENT) do
    source "WCAG 2.5.1 Pointer Gestures and 2.2 SC 2.5.7 Dragging Movements, AA; Clark, Designing for Touch"
    tags %i[ACCESSIBILITY]
    path Regexp.union(/_controller\.js\z/, S::SNAP::SNAPSHOT)
    reads_beyond_file true
    fix "Give every swipe or drag result a button calling the same method (click->stack#like); small and low is fine."
    bad S.controller
    good S.controller("  tap() { this.element.addEventListener(\"click\", () => this.like()) }")
    check { |src, path| S.untapped(src, path).map { |hit| finding(**hit) } }
    adapter(:rendered_ui, languages: %i[json], example_path: S::SNAP::EXAMPLE, bad: S.stack("touchend->stack#like"),
                          good: S.stack("touchend->stack#like", "click->stack#like"),
                          &S.rendered(:GESTURE_HAS_TAP_EQUIVALENT))
  end
end
