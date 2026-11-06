# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:48 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c02974934fcdbdca
require_relative "master/law/css"

Law.define(:NO_IMPORT_SCSS) do
  source "Sass best practice - @use over @import (Sass team)"
  detect { |line| line.match?(/@import\s+["']/) }
  fix "@import is deprecated. Use @use/@forward."
  bad  "@import \"base\";"
  good "@use \"base\";"
end
