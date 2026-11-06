# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:319 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 591c677a3e09bb2c
require_relative "master/law/recovered_design_semantics"

Law.define(:STYLE_FOLLOWS_STRUCTURE) do
  source "pub3 anti_divitis + anti_sectionitis - structure before decoration"
  ask "Before adding CSS selectors, wrappers, spacing hacks, or decorative rules, is the HTML structure itself semantic, minimal, and ordered for the content? Prefer changing the structural source over painting around a malformed hierarchy. Return CLEAN when semantic structure already carries the hierarchy and styling follows it."
  fix "Fix semantic structure and content hierarchy first; then simplify selectors and tokens to style that structure."
  bad <<~X
    <div class="content-wrapper">
      <div class="content-title">Orders</div>
      <div class="content-copy">No orders yet.</div>
    </div>

    .content-wrapper .content-title { margin-bottom: 13px; }
    .content-wrapper .content-copy { margin-top: 7px; }
  X
  good <<~X
    <section aria-labelledby="orders-title">
      <h2 id="orders-title">Orders</h2>
      <p>No orders yet.</p>
    </section>

    section { padding-block: 16px; }
    h2 { margin-block-end: 8px; }
  X
end
