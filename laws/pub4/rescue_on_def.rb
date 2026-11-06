# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:239 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 1663ec67be5df36c
require_relative "master/law/ruby"

Law.define(:RESCUE_ON_DEF) do
  source "Ruby Style Guide - rescue in method definitions"
  scope :file
  # Same /m defect as GUARD_CLAUSE above: the pattern spanned unrelated methods,
  # gluing a def to a rescue hundreds of lines away and reporting it at line 1.
  # A def-level rescue is a `begin` on the line directly after the def, which is
  # what the bad fixture shows.
  # The begin has to BE the body, which is what "put rescue on the def" means.
  # Unanchored, this matched a begin/rescue guarding one statement at the top of
  # a method — visual_contract.rb wraps its `require "selenium-webdriver"` that
  # way and then does fifteen more lines. Hoisting that rescue to the def would
  # widen it to catch a LoadError from anywhere in the method, which is the
  # opposite of the tightening the rule is asking for.
  #
  # The backreference pins the begin's `end` and the def's `end` to their own
  # indents, so the block only matches when nothing follows it.
  detect do |text|
    text.match?(/^([ \t]*)def \w+[^\n]*\n\1[ \t]+begin\n(?:(?!\1[ \t]*(?:def|end)\b)[^\n]*\n)*?\1[ \t]+rescue[^\n]*\n(?:(?!\1[ \t]*def )[^\n]*\n)*?\1[ \t]+end\n\1end\b/)
  end
  fix "Put rescue directly on the def block."
  bad <<~X
    def go
      begin
        run
      rescue Foo
      end
    end
  X
  good <<~X
    def go
      run
    rescue Foo
      nil
    end
  X
end
