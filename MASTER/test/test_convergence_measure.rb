# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/convergence/measure"

class TestConvergenceMeasure < Minitest::Test
  def test_all_five_trees_are_measured
    data = Master::Convergence::Measure.inventory(root: Master::REPO_ROOT)
    assert_equal MasterPaths::TREES.sort, data[:trees].keys.sort
    assert_operator data[:totals][:files], :>, 0
    assert_operator data[:totals][:bytes], :>, 0
  end

  def test_largest_files_are_sorted
    row = Master::Convergence::Measure.inventory(root: Master::REPO_ROOT)[:trees].fetch("MASTER")
    sizes = row[:largest].map { |entry| entry[:bytes] }
    assert_equal sizes.sort.reverse, sizes
  end
end
