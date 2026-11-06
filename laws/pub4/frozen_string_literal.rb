# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:23 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 513dac0a67071d3c
require_relative "master/law/ruby"

Law.define(:FROZEN_STRING_LITERAL) do
  source "Ruby Style Guide / RuboCop Style/FrozenStringLiteralComment"
  scope :file
  # Its subject IS a comment, so it has to be allowed to see one. Without this,
  # considered_text blanks line 1 before the detector reads it and the file looks
  # like it starts with a newline — which is exactly what the lookahead is
  # testing for. Measured before the fix: 423 of 423 files under MASTER/lib that
  # carry the magic comment were flagged as missing it. A law that fires on every
  # file it should pass is indistinguishable from one nobody wired up.
  reads_comments true
  # A shebang may precede it, and Ruby still honours it — proved rather than
  # assumed: a file whose line 1 is #!/usr/bin/env ruby and line 2 is the magic
  # comment freezes its literals, and the same file without the comment does not.
  # Anchored at \A this flagged all 24 executables in OPENBSD, RAILS/checks and
  # MASTER/tools that carry the comment in the only place a shebang leaves for it.
  detect { |text| !text.match?(/\A(?:#![^\n]*\n)?# frozen_string_literal/) }
  fix "Add '# frozen_string_literal: true' as the first line, or the line after a shebang."
  bad <<~X
    require "json"
  X
  good <<~X
    # frozen_string_literal: true
  X
end
