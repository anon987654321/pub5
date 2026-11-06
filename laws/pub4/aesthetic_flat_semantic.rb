# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rails.rb:50 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6ba6e212b54a3a46
require_relative "master/law/rails"

Law.define(:AESTHETIC_FLAT_SEMANTIC) do
  source "MASTER UI aesthetic - flat 8px-rhythm surfaces"
  ask "Score the UI surface for flat, pixel-precise design: reject ornamental shadow, blur, or glow; uneven spacing off an 8px rhythm; weak hierarchy; and decorative particles. Propose concrete token, spacing, and type fixes. Return CLEAN when already flat and rhythmic."
  fix "Remove ornamental depth, normalize spacing onto the 8px rhythm, strengthen hierarchy, and make decoration earn its place."
  bad <<~X
    .card {
      margin: 13px;
      box-shadow: 0 18px 50px rgba(0, 0, 0, .35);
      filter: blur(2px);
    }
  X
  good <<~X
    .card {
      margin: 16px;
      box-shadow: none;
      filter: none;
    }
  X
end
