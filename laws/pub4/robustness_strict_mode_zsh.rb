# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/laws.yml ROBUSTNESS_strict_mode_zsh by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a494140dbb6f94e3
require_relative "master/lib/master"

Law.define(:ROBUSTNESS_STRICT_MODE_ZSH) do
  source "pub4 MASTER/data/laws.yml ROBUSTNESS_strict_mode_zsh"
  practice "A zsh script with no -euo pipefail."
end
