# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:385 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c910a3783f991623
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:CONSECUTIVE_BLANK_LINES) do
    tags %i[HYGIENE]
    fix "no consecutive blank lines"
    bad "a = 1\n\n\nb = 2\n"
    good "a = 1\n\nb = 2\n"
    check do |src, path|
      findings = []
      prev_blank = false

      src.each_line.with_index(1) do |line, n|
        blank = line.strip.empty?
        findings << finding(line: n, message: "consecutive blank line") if blank && prev_blank
        prev_blank = blank
      end
      findings
    end
  end
      end
    end
  end
end
