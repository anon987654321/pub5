# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/check_chain"
require_relative "../lib/operator/readers"

# The governed trees are one list, MasterPaths::TREES. A second literal in lib/
# is a list that drifts the moment a tree is added or renamed.
class TestTreeListSingleSource < Minitest::Test
  TREES = MasterPaths::TREES

  # A %w[] literal whose words are exactly the governed trees is a second copy
  # of the one list, whatever its length. Deliberate subsets (the trees that
  # prove a pass, the trees an audit walks) are a different statement and are
  # not this guard's business.
  LITERAL = /%w\[([^\]]*)\]/

  def test_the_list_is_the_governed_trees
    assert_equal %w[MASTER RAILS OPENBSD STUDIO BIZ], MasterPaths::TREES
    assert_predicate MasterPaths::TREES, :frozen?
  end

  def test_the_named_constants_read_the_one_list
    {
      Master::Convergence => :ROOTS, Master::Core::Constitution => :REPO_TREES,
      Master::Fix::Reachability => :TOP_LEVEL_TREES,
      Operator::CheckChain => :TREES, Operator::Readers => :TREES, Master::Snapshot => :DEFAULT_TREES
    }.each do |owner, name|
      assert_equal MasterPaths::TREES, owner.const_get(name).to_a, "#{owner}::#{name}"
    end
    assert_same MasterPaths::TREES, Master::Convergence::ROOTS
  end

  def test_no_other_lib_file_spells_the_list
    lib = File.expand_path("../lib", __dir__)
    offenders = Dir.glob(File.join(lib, "**", "*.rb")).select do |path|
      next false if path.end_with?("boot/paths.rb")

      File.readlines(path).any? do |line|
        next false if line.lstrip.start_with?("#")

        line.scan(LITERAL).any? { |(words)| words.split == TREES }
      end
    end
    assert_empty offenders.map { |path| path.delete_prefix("#{lib}/") }
  end
end
