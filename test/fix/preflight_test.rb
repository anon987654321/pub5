# frozen_string_literal: true

require_relative "fix_helper"

# Moved from pub4 MASTER/test/test_fix_trace_drift.rb (850af52083): drift
# that only another writer's saves cause lets the run go on; a file that does
# not parse on a steady reading still refuses it. One /fix per tree.
class FixPreflightTest < Minitest::Test
  include FixHelper

  def test_a_steady_tree_that_parses_passes
    sandbox do |root|
      put(root, "a.rb", "x = 1\n")
      report = Fix::Preflight.check(fix_world(root), ["a.rb"], settle: -> {})

      assert_equal [[], []], [report.broken, report.drifting]
    end
  end

  def test_persistent_drift_alone_does_not_refuse_the_run
    sandbox do |root|
      put(root, "a.rb", "x = 1\n")
      world = fix_world(root)
      saves = 0
      world.define_singleton_method(:read) do |path|
        saves += 1
        "x = #{saves}\n"
      end
      report = Fix::Preflight.check(world, ["a.rb"], settle: -> {})

      assert_equal ["a.rb"], report.drifting
      assert_empty report.broken
    end
  end

  def test_drift_beside_a_real_failure_still_refuses
    sandbox do |root|
      put(root, "broken.rb", "def x(\n")
      put(root, "moving.rb", "x = 1\n")
      world = fix_world(root)
      saves = 0
      plain = world.method(:read)
      world.define_singleton_method(:read) { |path| path == "moving.rb" ? "x = #{saves += 1}\n" : plain.call(path) }
      report = Fix::Preflight.check(world, %w[broken.rb moving.rb], settle: -> {})

      assert_equal ["moving.rb"], report.drifting
      assert_equal ["broken.rb"], report.broken.map(&:first)
    end
  end

  def test_one_fix_per_tree
    sandbox do |root|
      world = fix_world(root)
      put(root, Fix::Preflight.lock_path("."), "#{Process.ppid}\n")
      assert_raises(Core::Refusal) { Fix::Preflight.lock!(world, ".") }

      put(root, Fix::Preflight.lock_path("."), "999999\n")
      path = Fix::Preflight.lock!(world, ".")
      assert_equal "#{Process.pid}\n", File.read(File.join(root, path)), "a dead holder's lock is taken over"
      Fix::Preflight.release(world, path)
      assert_empty File.read(File.join(root, path))
    end
  end
end
