# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rails.rb:70 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6001ed95deab0ff7
require_relative "master/law/rails"

Law.define(:AESTHETIC_RAMS_SEMANTIC) do
  source "Dieter Rams - useful, understandable, unobtrusive, honest, thorough"
  ask "Apply useful, understandable, unobtrusive, honest, and thorough to this UI surface. Flag dishonest progress, missing empty or error states, or chrome that competes with content. Return CLEAN when the surface is solid."
  fix "Make the primary state useful and legible, represent progress and failure honestly, cover empty states, and remove chrome that competes with the content."
  bad <<~X
    <div class="dashboard">
      <div class="spinner">100%</div>
      <div class="content"></div>
    </div>
  X
  good <<~X
    <main class="dashboard">
      <h1>Orders</h1>
      <p>No orders yet.</p>
    </main>
  X
end
