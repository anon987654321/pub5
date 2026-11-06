# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../laws/engine"
require_relative "../../laws/pub4/master/lib/master"
require_relative "../../master/port/pub4_laws"

# bin/master port-laws: the mechanical split of a pub4 law file, the broken
# and unported rows the engine keeps, and the write exception a port has.
class PortTest < Minitest::Test
  include TestHelper

  def teardown = Law.reset!

  PUB4 = <<~RUBY
    # frozen_string_literal: true

    module Master
      module Laws
        WORD = /TODO/
        limit = 3

        ::Law.define(:NO_TODO) do
          detect { |line| line.match?(WORD) && limit.positive? }
          fix "Finish it."
          bad "x # TODO\\n"
          good "x\\n"
        end

        %w[ONE TWO].each do |n|
          ::Law.define(:"PAIR_\#{n}") do
            practice "pair \#{n}"
          end
        end
      end
    end
  RUBY

  def test_a_define_moves_with_its_modules_and_the_locals_it_reads
    split = Port::Pub4Laws.split("sample.rb", PUB4)
    simple = split.units.find { |u| u.id == "NO_TODO" }
    assert_equal ["module Master", "module Laws"], simple.nesting
    assert_equal ["    limit = 3"], simple.prelude
    refute_includes split.support, "Law.define"
    assert_includes split.support, "WORD = /TODO/"
    looped = split.units.find(&:loop)
    assert_equal "%w[ONE TWO]", looped.loop.receiver
    assert_includes Port::Pub4Laws.unrolled(looped, ".values_at(1)"), "%w[ONE TWO].values_at(1).each do |n|"
    assert_empty split.refused
  end

  def test_a_define_the_split_cannot_carry_is_refused_with_its_reason
    split = Port::Pub4Laws.split("odd.rb", "if true\n  Law.define(:ODD) { practice %q(p) }\nend\n")
    assert_equal 1, split.refused.size
    assert_match(/not a module, class or each loop/, split.refused.first.last)
  end

  def test_a_hand_edit_is_seen_by_its_digest
    text = Port::Pub4Laws.stamped(["# header\n"], "body\n")
    refute Port::Pub4Laws.edited?(text)
    assert Port::Pub4Laws.edited?(text.sub("body", "edited"))
    assert Port::Pub4Laws.edited?("# written by hand\n")
  end

  def row(**over)
    { "statement" => "s", "kind" => "lexical", "severity" => "error", "lifecycle" => "advisory",
      "autofix" => "never", "enacted" => "2026-11-06", "file" => "laws/sample.rb" }.merge(over.transform_keys(&:to_s))
  end

  def test_an_imported_law_judges_a_file_under_its_pub4_name
    assert_equal "RAILS/brgen/app/x.rb", Law::Pub4.name("rails/brgen/app/x.rb")
    assert_equal "MASTER/lib/world.rb", Law::Pub4.name("core/world.rb")
    assert Law.terminal_output?(Law::Pub4.name("core/world.rb"))
    refute Law.terminal_output?(Law::Pub4.name("rails/brgen/app/views/a.html.erb"))
    Law.instance_variable_set(:@rows, { "RAILS_ONLY" => row(file: "laws/pub4/rails_only.rb", pub4: { "id" => "R", "source" => "s" }) })
    law = Law.define(:RAILS_ONLY) do
      path "RAILS/"
      detect { |line| line.include?("puts") }
      bad "puts 1\n"
      good "log 1\n"
      fix "f"
    end
    assert_predicate law, :imported?
    assert_equal 1, law.scan("puts 1\n", "rails/brgen/app/a.rb").size
    assert_empty law.scan("puts 1\n", "studio/a.rb")
  ensure
    Law.instance_variable_set(:@rows, nil)
  end

  def test_only_the_named_port_command_writes_its_ported_glob
    sandbox do |root|
      ported = { "laws/pub4/**/*" => { "from" => ["pub4"], "by" => "port-laws" } }
      verbs = { write: ["laws/**/*"] }
      mine = Core::Manifest.new(name: "port-laws", verbs:, root:, protected_paths: ["laws/**"], generated: {}, ported:)
      other = Core::Manifest.new(name: "fix", verbs:, root:, protected_paths: ["laws/**"], generated: {}, ported:)
      assert mine.check!(:write, "laws/pub4/a.rb")
      assert_raises(Core::Refusal) { other.check!(:write, "laws/pub4/a.rb") }
      assert_raises(Core::Refusal) { mine.check!(:write, "laws/engine.rb") }
    end
  end
end
