# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/shell.rb:140 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 83af870df66ca7ea
require_relative "master/law/shell"

Law.define(:STRICT_MODE_ZSH) do
  source "Shell strict mode set -euo pipefail (Google Shell Style Guide)"
  scope :file
  # A law that fires on what is MISSING cannot be silenced by blanking a line,
  # which is all `scan: intentional` does — considered_text removes the marker
  # and the absent `set -e` is still absent. `absent` is checked against the raw
  # text before that, so it is the opt-out an absence-based law can honour, and
  # an all-night rotation script needs one: aborting on the first non-zero exit
  # would end the night at its first failed render.
  absent %r{scan:\s*intentional}
  # Only a shell shebang, not any shebang: a #!/usr/bin/env ruby script has no
  # set -euo pipefail to add, and flagging one is the false positive an
  # extensionless bin/ tool trips when its language cannot be read from a suffix.
  #
  # Two more shapes are not missing strict mode. `#!/bin/bash -e` sets it on the
  # shebang. An rc.d(8) script sources rc.subr, whose functions return non-zero
  # as control flow, so strict mode there stops the daemon script mid-check.
  detect do |text|
    text.match?(%r{\A#![^\n]*\b(?:sh|bash|zsh|ksh|dash)\b}) &&
      !text.match?(/^\s*set\s+-[eE]/) &&
      !text.match?(/\A#![^\n]*\s-[a-zA-Z]*e/) &&
      !text.match?(%r{^\s*\.\s+/etc/rc\.d/rc\.subr\b})
  end
  fix "Add 'set -euo pipefail' after shebang."
  bad <<~X
    #!/usr/bin/env zsh
    echo hi
  X
  good <<~X
    #!/usr/bin/env zsh
    # what this script does
    set -euo pipefail
  X
end
