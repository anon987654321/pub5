# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:325 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c0b06e8c3b7f0ec2
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:SILENT_RESCUE) do
    tags %i[ERROR_HANDLING FAIL_VISIBLY]
    fix "blanket rescue discards error without logging or re-raising"
    bad "begin\n  risky\nrescue StandardError\n  nil\nend\n"
    good "begin\n  risky\nrescue StandardError => e\n  warn e\nend\n"
    check do |src, path|
      # No path exemption for the scanner's own rules: a rule that returns [] on
      # error calls the file it failed on clean, so a swallow costs more in this
      # directory than anywhere else. The one exception is the rule's own test,
      # which must spell every shape it proves — the law-conduct argument.
      next [] if path.to_s.match?(/test_silent_rescue_rule\.rb\z|test_self_test\.rb\z/)

      SilentRescue.scan(src, narrow: false).map { |hit| finding(line: hit[:line], message: hit[:message]) }
    end
  end
      end
    end
  end
end
