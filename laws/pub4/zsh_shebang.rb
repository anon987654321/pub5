# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb:90 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d91d7839ffd1edc6
require_relative "master/law/shell"

Law.define(:ZSH_SHEBANG) do
  source "House rule: zsh, not bash - no bash in OpenBSD base, zsh is the operator dialect"
  scope :file
  detect { |text| text.match?(%r{\A#![^\n]*\bbash\b}) }
  fix "Use #!/usr/bin/env zsh, or #!/bin/sh when vm23 must run it."
  bad <<~X
    #!/bin/bash
    set -euo pipefail
  X
  good <<~X
    #!/usr/bin/env zsh
    set -euo pipefail
  X
end
