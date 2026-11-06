# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:341 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 74bb962f594be246
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:NARROW_SILENT_RESCUE) do
    tags %i[ERROR_HANDLING]
    fix "narrow-class rescue discards error without logging or re-raising"
    bad "begin\n  risky\nrescue Errno::ENOENT\n  nil\nend\n"
    good "begin\n  risky\nrescue Errno::ENOENT => e\n  warn e\nend\n"
    check do |src, path|
      SilentRescue.scan(src, narrow: true).map { |hit| finding(line: hit[:line], message: hit[:message]) }
    end
  end
      end
    end
  end
end
