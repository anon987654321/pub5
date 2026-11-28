# frozen_string_literal: true

require_relative "test_helper"

# The fleet check starts the RAILS layout browser sweep, which takes minutes and says nothing about one
# Ruby file. It belongs to a whole-tree run, not to any path that happens to sit inside a tree.
class TestReachabilityScope < Minitest::Test
  # A Reachability whose fleet check records that it ran instead of starting a browser.
  def reachability(sweeps)
    Master::Fix::Reachability.new(root: Master::ROOT).tap do |reach|
      reach.define_singleton_method(:verify_fleet!) { |defer_rendered: false| sweeps << (defer_rendered ? :wiring_only : :fleet) }
    end
  end

  def collected(target) = Master::Fix::FixLoop::FileCollector.new(root: Master::ROOT).collect(target)

  def test_a_file_inside_a_tree_does_not_start_the_fleet_sweep
    sweeps = []
    file = File.join(Master::ROOT, "lib", "cli", "fold_risk.rb")

    reachability(sweeps).verify!(file, files: [file])

    assert_empty sweeps
  end

  def test_a_directory_inside_a_tree_does_not_start_the_fleet_sweep
    sweeps = []
    dir = File.join(Master::ROOT, "lib", "cli", "pipeline")

    reachability(sweeps).verify!(dir, files: collected(dir))

    assert_empty sweeps
  end

  def test_the_whole_tree_still_starts_it
    sweeps = []

    reachability(sweeps).verify!(Master::ROOT, files: collected(Master::ROOT))

    assert_equal [:fleet], sweeps
  end

  def test_deferred_rendering_still_checks_fleet_wiring
    sweeps = []
    reach = reachability(sweeps)
    assert reach.verify!(Master::ROOT, files: collected(Master::ROOT), defer_rendered: true)
    assert_equal [:wiring_only], sweeps
  end

  def test_grouped_rendering_discards_the_pre_pass_capture
    reach = reachability([])
    reach.instance_variable_set(:@layout_sweep, :old)
    reach.define_singleton_method(:observe_rendered_fleet!) do
      raise "old capture survived" unless layout_sweep.nil?
      @layout_sweep = :fresh
    end
    reach.capture_rendered_fleet!
    assert_equal :fresh, reach.layout_sweep
  end

  # --blockers narrows the corpus to the files a red check named: fewer than the collector's, never more.
  def test_a_declared_subset_is_reached_and_a_file_outside_it_is_not
    dir = File.join(Master::ROOT, "lib", "cli", "pipeline")
    reach = reachability([])
    some = collected(dir).first(2)

    assert_raises(RuntimeError) { reach.verify!(dir, files: some) }
    assert reach.verify!(dir, files: some, subset: true)
    outside = File.join(Master::ROOT, "README.md")
    assert_raises(RuntimeError) { reach.verify!(dir, files: some + [outside], subset: true) }
  end
end
