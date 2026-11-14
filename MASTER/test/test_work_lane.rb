# frozen_string_literal: true

require_relative "test_helper"
require "fix/work_lane"
require "fix/reachability"
require "cli/command_registry/review"

# A RAILS /fix measured for fifty minutes before its first repair. The lane decides which
# of those stages a run starts; these tests pin what each lane runs and skips.
class TestWorkLane < Minitest::Test
  Lane = Master::Fix::WorkLane

  def setup = @lane = Lane.current

  def teardown = Lane.restore(@lane)

  def test_code_is_the_default_and_starts_no_browser_research_or_architecture
    assert_equal :code, Lane::DEFAULT
    assert Lane.runs?(:code_passes, :code)
    %i[research architecture layout_sweep browser_checks visual_pass visual_groups].each do |stage|
      refute Lane.runs?(stage, :code), "code lane must skip #{stage}"
    end
  end

  # The bare default on a rendered target (Johann 2026-11-07): a plain /fix over a RAILS
  # path reads the rendered surface — layout, browser checks, screenshots, visual review —
  # alongside the code passes, but asks for no research/architecture and no grouped repair.
  def test_standard_is_the_rendered_target_default_and_sees_the_pages
    assert Lane.runs?(:code_passes, :standard)
    %i[layout_sweep browser_checks screenshot_sweep visual_pass].each do |stage|
      assert Lane.runs?(stage, :standard), "standard lane must run #{stage}"
    end
    %i[research architecture visual_groups].each do |stage|
      refute Lane.runs?(stage, :standard), "standard lane must skip #{stage}"
    end
  end

  def test_the_default_lane_follows_the_target
    assert_equal :standard, Lane.default_lane("RAILS")
    assert_equal :standard, Lane.default_lane("RAILS/brgen")
    assert_equal :standard, Lane.default_lane("/pub5/RAILS/mrdamascy")
    assert_equal :code, Lane.default_lane("MASTER")
    assert_equal :code, Lane.default_lane(".")
  end

  def test_visual_sweeps_once_and_groups_without_the_code_passes
    %i[layout_sweep browser_checks visual_groups].each { |stage| assert Lane.runs?(stage, :visual), stage }
    %i[research architecture visual_pass code_passes].each do |stage|
      refute Lane.runs?(stage, :visual), "visual lane must skip #{stage}"
    end
  end

  def test_all_runs_research_rendering_grouped_visual_and_every_elevation_stage
    %i[research architecture layout_sweep browser_checks screenshot_sweep visual_pass visual_groups code_passes
       improve_code improve_prose improve_visual improve_music ideate restructure_drive].each do |stage|
      assert Lane.runs?(stage, :all), "all lane must run #{stage}"
    end
  end

  def test_rendered_target_detection_is_shared_and_case_insensitive
    assert Lane.rendered_target?("RAILS")
    assert Lane.rendered_target?("/repo/pub5/rails/brgen")
    refute Lane.rendered_target?("BIZ")
    refute Lane.rendered_target?("MASTER")
  end

  def test_the_summary_names_the_lane_and_what_it_skipped
    summary = Lane.summary(:code)

    assert_includes summary, "lane=code"
    assert_includes summary, "layout sweep"
    assert_includes summary, "research0 web research"
    assert_includes summary, "rendered findings are not measured or proven"
    refute_includes Lane.summary(:visual), "not measured"
    refute_includes Lane.summary(:standard), "not measured"
  end

  def test_visual_lane_is_rails_only
    assert_nil Lane.refusal("RAILS", :visual)
    assert_nil Lane.refusal(File.join(Master::REPO_ROOT, "RAILS", "brgen"), :visual)
    assert_match(/RAILS/, Lane.refusal("MASTER", :visual))
    assert_nil Lane.refusal("MASTER", :code)
  end

  def test_unknown_lane_is_refused
    assert_raises(ArgumentError) { Lane.parse("fast") }
    assert_equal :visual, Lane.parse("Visual")
  end

  # The conversation stage rides every lane that claims to repair the product: the
  # deterministic suite costs no model, and a run that never asks how the replies
  # read would claim the product while measuring only laws. The visual lane is the
  # exception - it renders RAILS, and the conversation surface is MASTER's.
  def test_conversation_rides_code_standard_and_all_but_not_visual
    %i[code standard all].each do |lane|
      assert Lane.runs?(:conversation, lane), "#{lane} lane must run the conversation probe"
    end
    %i[visual].each do |lane|
      refute Lane.runs?(:conversation, lane), "#{lane} lane must skip the conversation probe"
    end
    assert_equal "conversation UX probe", Lane::STAGES.fetch(:conversation)
    assert_includes Lane.summary(:visual), "conversation UX probe"
    refute_includes Lane.summary(:code), "conversation UX probe"
  end
end

# Where the lane reaches: the /fix flag, the child check runner, the layout suite and the
# fleet check that starts the sweep.
class TestWorkLaneWiring < Minitest::Test
  Lane = Master::Fix::WorkLane

  def setup = @lane = Lane.current

  def teardown = Lane.restore(@lane)

  def test_fix_reads_the_lane_flag_per_dispatch_and_keeps_it_out_of_the_target
    registry = Master::CLI::CommandRegistry

    assert_equal "visual", registry.execution_overrides("RAILS --lane=visual")[:lane]
    # A bare rendered target earns the standard lane; a bare MASTER stays code.
    assert_equal "standard", registry.execution_overrides("RAILS")[:lane]
    assert_equal "standard", registry.execution_overrides("RAILS/mrdamascy")[:lane]
    assert_equal "code", registry.execution_overrides("MASTER")[:lane]
    assert_equal "code", registry.execution_overrides("RAILS --lane=code")[:lane]
    assert_equal "RAILS", registry.parse_pass_flags("RAILS --lane=code").last
  end

  # Two words used to match nothing: the run took the code lane and "all" joined the target.
  def test_the_lane_flag_reads_as_two_words_and_names_every_lane
    registry = Master::CLI::CommandRegistry

    assert_equal "all", registry.execution_overrides(". --lane all")[:lane]
    assert_equal ". --lane=all", registry.lane_flag_joined(". --lane all")
    assert_equal "elevate", registry.execution_overrides("RAILS --lane=elevate")[:lane]
    assert_raises(ArgumentError) { Lane.parse(registry.execution_overrides("RAILS --lane=everything")[:lane]) }
  end

  def test_fix_reads_the_task_intent_flag_and_keeps_it_out_of_the_target
    registry = Master::CLI::CommandRegistry

    assert_equal "content_only", registry.execution_overrides("RAILS --intent=content_only")[:task_intent]
    assert_equal "RAILS", registry.parse_pass_flags("RAILS --intent=content_only").last
    assert_equal "not_a_contract", registry.execution_overrides("RAILS --intent=not_a_contract")[:task_intent]
    assert_equal "dry", registry.execution_overrides("RAILS --autofix=dry")[:autofix_mode]
    assert_equal "12", registry.execution_overrides("RAILS --max-files=12")[:max_files]
    assert_equal true, registry.execution_overrides("RAILS --blockers")[:blockers]
    assert_equal "on", registry.execution_overrides("RAILS --autofix=dry --autofix=on")[:autofix_mode]
  end

  def test_the_check_runner_is_told_the_lane
    assert_equal({ "CHECK_LANE" => "code" }, Lane.check_env(:code))
  end

  # The rendered suite is the 214-cell browser sweep; a code-lane proof measures the source leaves only.
  def test_the_layout_suite_leaves_out_the_rendered_suite_in_the_code_lane
    require File.expand_path("../checks/lib/layout_suite", __dir__)
    saved = ENV.fetch("CHECK_LANE", nil)

    ENV["CHECK_LANE"] = "code"
    refute_includes Deploy::LayoutSuiteCheck.new.leaves, Deploy::RenderedSuiteCheck
    ENV["CHECK_LANE"] = "standard"
    assert_includes Deploy::LayoutSuiteCheck.new.leaves, Deploy::RenderedSuiteCheck
    ENV["CHECK_LANE"] = "visual"
    assert_includes Deploy::LayoutSuiteCheck.new.leaves, Deploy::RenderedSuiteCheck
  ensure
    saved.nil? ? ENV.delete("CHECK_LANE") : ENV["CHECK_LANE"] = saved
  end

  # The fleet check verifies wiring in every lane; only a lane that renders starts the sweep.
  def test_reachability_starts_the_layout_sweep_only_in_a_rendering_lane
    rails = File.join(Master::REPO_ROOT, "RAILS")
    files = Master::Fix::FixLoop::FileCollector.new(root: Master::ROOT).collect(rails)

    { code: [], standard: [:sweep], visual: [:sweep], all: [:sweep] }.each do |lane, expected|
      Lane.set!(lane)
      sweeps = []
      reach = Master::Fix::Reachability.new(root: Master::ROOT)
      reach.define_singleton_method(:observe_layout_suite!) { sweeps << :sweep }
      reach.verify!(rails, files:)

      assert_equal expected, sweeps, "lane #{lane}"
    end
  end
end
