# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/convergence/measure"

class TestConvergenceMeasure < Minitest::Test
  def test_all_five_trees_are_measured
    data = Master::Convergence::Measure.inventory(root: Master::REPO_ROOT)
    assert_equal MasterPaths::TREES.sort, data[:trees].keys.sort
    assert_operator data[:totals][:files], :>, 0
    assert_operator data[:totals][:bytes], :>, 0
  end

  def test_inventory_does_not_follow_symlinks_or_duplicate_tree_prefixes
    Dir.mktmpdir do |root|
      tree = File.join(root, "MASTER")
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, "source.rb"), "x = 1\n")
      outside = File.join(root, "outside.rb")
      File.write(outside, "outside\n")
      File.symlink(outside, File.join(tree, "external.rb"))
      File.symlink(tree, File.join(root, "RAILS"))

      row = Master::Convergence::Measure.tree_inventory("#{root}/", "MASTER")
      assert_equal 1, row[:files]
      assert_equal 1, row[:ruby_lines]
      assert_equal ["MASTER/source.rb"], row[:largest].map { |entry| entry[:path] }
      assert_equal 0, Master::Convergence::Measure.tree_inventory(root, "RAILS")[:files]
      assert_includes Master::Convergence::Measure.render(root:), "largest MASTER/source.rb bytes=6"
      refute_includes Master::Convergence::Measure.render(root:), "MASTER/MASTER/"
    end
  end

  def test_largest_files_are_sorted
    row = Master::Convergence::Measure.inventory(root: Master::REPO_ROOT)[:trees].fetch("MASTER")
    sizes = row[:largest].map { |entry| entry[:bytes] }
    assert_equal sizes.sort.reverse, sizes
  end
end
