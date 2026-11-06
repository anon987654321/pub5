# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/recovered_design_semantics.rb:39 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ebc7e7fa4072b60c
require_relative "master/law/recovered_design_semantics"

Law.define(:HTML_HEADING_HIERARCHY) do
  source "pub prompt lineage - semantic HTML5 structure; h1 for title, h2 for sections, h3 for subsections"
  ask "Does the rendered document expose a coherent heading hierarchy? Require one meaningful page heading, then descend one level at a time through sections; do not use heading tags for visual sizing or skip from h1 to h3 merely for styling. Return CLEAN when the hierarchy matches the information architecture."
  fix "Use heading levels to express document structure, then control visual size with typography tokens instead of heading-tag jumps."
  bad <<~X
    <h1>Orders</h1>
    <h3>Recent orders</h3>
    <h4>Today</h4>
  X
  good <<~X
    <h1>Orders</h1>
    <h2>Recent orders</h2>
    <h3>Today</h3>
  X
end
