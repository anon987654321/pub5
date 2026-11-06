# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:224 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9304d26658e4a55c
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:NO_SILENT_TEST_SKIP) do
    path %r{(?:\A|/)(?:test|spec)/}
    tags %i[COMPLETENESS]
    fix "a test skipped without saying why"
    bad "  def test_parse\n    skip\n  end\n"
    good "  def test_parse\n    skip \"needs /proc\" unless File.readable?(\"/proc/meminfo\")\n  end\n"
    # Proved as a test file: the catalogue scopes it to test/ and spec/.
    example_path "/repo/test/test_parse.rb"
    check do |src, path|
      lines = src.lines
      lines.each_with_index.filter_map do |line, index|
        bare_ruby = line.match?(/\A\s*skip\s*(?:\(\s*\)|""|'')?\s*(?:(?:if|unless)\b.*)?\z/)
        bare_js = line.match?(/\b(?:xit|xdescribe|xtest|(?:it|test|describe)\.skip)\s*\(/) &&
                  !lines[index - 1].to_s.match?(%r{\A\s*(?://|/\*|\*)}) && index.positive?
        next unless bare_ruby || bare_js

        finding(line: index + 1, message: "skipped without a reason - say why, or fix the test")
      end
    end
  end
      end
    end
  end
end
