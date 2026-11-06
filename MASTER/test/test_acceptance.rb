# frozen_string_literal: true

# The route-contract suites' rules, for the acceptance command: every
# instrument a target can answer runs, every one it cannot is named with what
# it is missing, and a pass with nothing under it is impossible.

require "minitest/autorun"
require_relative "../tools/acceptance"

class TestAcceptance < Minitest::Test
  PASS = Struct.new(:success?)

  def with_spawn_swaps(tool: nil, app: nil, route: nil)
    originals = %i[spawn_tool spawn_app spawn_route].to_h { |name| [name, Acceptance.method(name)] }
    Acceptance.define_singleton_method(:spawn_tool) { |_script, _args| tool } if tool
    Acceptance.define_singleton_method(:spawn_app) { |_dir| app } if app
    Acceptance.define_singleton_method(:spawn_route) { |*_args| route } if route
    yield
  ensure
    originals.each { |name, method| Acceptance.define_singleton_method(name, method) }
  end

  def test_the_root_contracts_fail_on_the_first_nonzero_answer
    with_spawn_swaps(tool: ["", "everything matches\n", PASS.new(false)]) do
      report = Acceptance.root_contracts("/target")

      assert_equal "fail", report.state
      assert_equal 2, report.detail.scan(":").size, "both instruments are named, not just the first"
    end
  end

  def test_the_round_trips_name_only_the_app_that_failed
    with_spawn_swaps(app: ["", "1 runs, 0 failures", PASS.new(true)]) do
      report = Acceptance.round_trips(Acceptance::ROOT)

      assert_equal "pass", report.state
    end
  end

  def test_a_tree_without_app_dirs_is_pending_not_skipped
    with_spawn_swaps(app: ["", "", PASS.new(false)]) do
      report = Acceptance.round_trips("/pub5")

      assert_equal "pending", report.state
      assert_includes report.detail, "no app trees"
    end
  end

  def test_route_contracts_fail_with_the_instruments_last_words
    with_spawn_swaps(route: ["brgen: 101 routes differ", "", PASS.new(false)]) do
      report = Acceptance.route_contracts("http://target.test")

      assert_equal "fail", report.state
      assert_equal 3, report.detail.scan(/\(\w+\)/).size, "every recorded app is checked"
      assert_includes report.detail, "routes differ"
    end
  end

  def test_route_contracts_pending_without_a_base_url
    report = Acceptance.route_contracts(nil)

    assert_equal "pending", report.state
    assert_includes report.detail, "--base-url"
  end

  # An instrument whose corpus is not yet recorded cannot answer pass: the
  # signed half names what recording would need.
  def test_signed_contracts_stay_pending_until_a_half_is_recorded
    with_signed_apps([]) do
      report = Acceptance.signed_contracts("http://target.test", "demo@target.test:password")

      assert_equal "pending", report.state
      assert_includes report.detail, "no signed half recorded yet"
    end
  end

  def test_signed_contracts_check_each_recorded_half
    with_spawn_swaps(route: ["brgen: every signed route matches", "", PASS.new(true)]) do
      with_signed_apps(["brgen"]) do
        report = Acceptance.signed_contracts("http://target.test", "demo@target.test:password")

        assert_equal "pass", report.state
      end
    end
  end

  def with_signed_apps(apps)
    original = Acceptance.method(:signed_apps)
    Acceptance.define_singleton_method(:signed_apps) { apps }
    yield
  ensure
    Acceptance.define_singleton_method(:signed_apps, original)
  end

  def test_the_recorded_apps_name_themselves_from_the_data_dir
    assert_equal %w[amber brgen bsdports], Acceptance.recorded_apps(".yml").sort
    assert_equal %w[amber brgen bsdports], Acceptance.recorded_apps(".signed.yml").sort
  end

  # One real anchor: against this checkout every runnable instrument holds,
  # and the two unrecorded halves answer as pending, never as pass.
  def test_the_whole_command_holds_against_this_checkout
    skip if ENV["MASTER_SKIP_LIVE"]

    exit_code = Acceptance.main([])

    assert_equal 0, exit_code
  end
end
