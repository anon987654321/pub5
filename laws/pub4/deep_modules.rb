# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:626 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: eb7cb90702c0504c
require_relative "master/law/universal"

Law.define(:DEEP_MODULES) do
  source "A Philosophy of Software Design (John Ousterhout)"
  ask "Is this module shallow, exposing a complex interface while doing little work behind it?"
  fix "Absorb complexity behind a small interface that provides substantial capability."
  bad <<~'X'
    service.call(a, b, c, d, e, f, g, h)
  X
  good <<~'X'
    service.call(request)
  X
end
