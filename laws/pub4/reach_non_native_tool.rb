# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml REACH_non_native_tool by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 39b6c90c806fac7f
require_relative "master/lib/master"

Law.define(:REACH_NON_NATIVE_TOOL) do
  source "pub4 MASTER/data/laws.yml REACH_non_native_tool"
  practice "A zsh script reaching for a GNU text tool not on the host."
end
