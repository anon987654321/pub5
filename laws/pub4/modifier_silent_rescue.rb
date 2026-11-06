# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:356 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 97acf7b6fa797a86
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:MODIFIER_SILENT_RESCUE) do
    tags %i[ERROR_HANDLING]
    fix "modifier rescue binds a discarded error to a name"
    bad "value = parse(raw) rescue nil\n"
    good "File.delete(path) rescue nil\n"
    check do |src, path|
      scan_lines(without_law_fixtures(without_comment_lines(without_regex_literals(src))),
                 MODIFIER_RESCUE_DISCARD, message: "modifier rescue binds nil on failure - bind a meaningful value")
    end
  end
      end
    end
  end
end
