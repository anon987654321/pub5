# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:493 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1fb6a92cd34a9aaa
require_relative "master/law/ruby"

Law.define(:DIRNAME_FILE) do
  source "Polished Ruby Programming, 2nd ed. (Jeremy Evans, 2026) - prefer __dir__"
  detect { |line| line.match?(/File\.dirname\(__FILE__\)/) }
  fix "Use __dir__."
  bad  "File.expand_path(File.dirname(__FILE__))"
  good "File.expand_path(__dir__)"
end
