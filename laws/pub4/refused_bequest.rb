# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:1677 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: c0f8adaf82dd0ea8
require_relative "master/law/universal"

Law.define(:REFUSED_BEQUEST) do
  source "Refactoring - Refused Bequest (Fowler)"
  ask "Does a subtype or variant inherit capabilities it cannot honor and then reject or ignore most of them?"
  fix "Choose an abstraction that matches the subtype's real contract or use composition."
  bad <<~'X'
    class ReadOnly < Writable; def write; raise NotImplementedError; end; end
  X
  good <<~'X'
    class ReadOnly < Readable; end
  X
end
