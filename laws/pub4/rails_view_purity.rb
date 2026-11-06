# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rails.rb:34 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1a4a619174160324
require_relative "master/law/rails"

Law.define(:RAILS_VIEW_PURITY) do
  source "MASTER Rails architecture - view purity"
  ask "If this is a Rails view or partial, does it contain queries, persistence, or multi-step business condition trees that belong in helpers, models, or presenters? Prefer CLEAN when it only presents assigns."
  fix "Move business logic out of the view; pass prepared assigns and use focused presentation helpers or presenters."
  bad <<~X
    <% orders = Order.where(user_id: current_user.id).select { |o| o.total > 1000 } %>
    <% orders.each { |order| order.update!(reviewed: true) } %>
    <%= orders.count %>
  X
  good <<~X
    <% @orders.each do |order| %>
      <%= render order %>
    <% end %>
  X
end
