# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/interface.rb:7 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 66508823be71904c
require_relative "master/law/interface"

Law.define(:NO_TRANSPORT_WRAPPER_IN_SOURCE) do
  source "MASTER source integrity - presentation wrappers do not belong in source files"
  scope :file
  detect do |text|
    text.match?(/\A\s*<(?:sub|sup|pre|code)>/i) ||
      text.match?(/\n\s*<\/(?:sub|sup|pre|code)>\s*\z/i)
  end
  fix "Remove presentation/transport wrapper markup from the source file and preserve its Ruby contents verbatim."
  bad <<~'X'
    <sub>
    # frozen_string_literal: true
    require "fileutils"
    end
    </sub>
  X
  good <<~'X'
    # frozen_string_literal: true

    require "fileutils"

    def run = true
  X
end
