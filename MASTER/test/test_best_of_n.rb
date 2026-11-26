# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "tmpdir"
require File.expand_path("../lib/fix/best_of_n", __dir__)

# Candidates are CSS strings; the fake renderer reads the file the pass just
# wrote and answers with a payload whose quality depends on it. That proves the
# selection (regressions dropped, best score wins, smallest diff breaks ties)
# and that the original is back on disk after every candidate.
class BestOfNTest < Minitest::Test
  Surface = Struct.new(:id, :viewport)
  B = Master::Fix::BestOfN
  S = Master::Fix::LayoutScoreStore

  def setup
    @root = Dir.mktmpdir("bon")
    FileUtils.mkdir_p(File.join(@root, "RAILS/__shared"))
    File.write(File.join(@root, "RAILS/__shared/design_tokens.yml"),
               YAML.dump("scale" => { "space_px" => [0, 4, 8, 16, 24, 32] }))
    @surface = Surface.new("brgen/home/mobile", "mobile")
    @path = File.join(@root, "card.scss")
    @original = ".a { margin: 13px; }\n"
    File.write(@path, @original)
    S.seed(@surface, rendering("mid"), root: @root)
  end

  def teardown = FileUtils.remove_entry(@root)

  def el(x, y, **over) = { "key" => "k#{x}#{y}", "visible" => true, "onscreen" => true, "tag" => "p", "text" => "t", "rect" => { "x" => x, "y" => y, "w" => 300, "h" => 30 } }.merge(over)

  # mid: a few edges, gaps half on scale; good: aligned and on scale; bad: ragged
  def rendering(kind)
    gaps, xs = { "good" => [[16, 16, 16], [16] * 6], "mid" => [[16, 13, 16], [16, 16, 16, 40, 16, 16]], "bad" => [[13, 19, 7], (0..11).map { |i| 3 + i * 17 }] }.fetch(kind)
    { "vw" => 400, "vh" => 800, "gaps" => gaps.map { |g| { "gap" => g } }, "elements" => xs.each_with_index.map { |x, i| el(x, i * 46, "line_height" => 24) } }
  end

  def measurer = ->(_surfaces, root:) { [[@surface, rendering(File.read(@path)[/kind-(\w+)/, 1] || "mid")]] }
  def read = -> { File.read(@path) }
  def write = ->(src) { File.write(@path, src) }
  def rebuild = -> { true }

  def rank(*candidates, **over)
    B.rank(candidates, original: @original, surfaces: [@surface], root: @root, measurer:, read:, write:, rebuild:, **over)
  end

  def test_the_best_scoring_candidate_wins_and_the_original_is_restored
    good = ".a { margin: 16px; } /* kind-good */\n"
    mid = ".a { margin: 12px; } /* kind-mid */\n"
    assert_equal good, rank(mid, good)
    assert_equal @original, File.read(@path)
  end

  def test_regressing_candidates_are_discarded
    bad = ".a { margin: 3px; } /* kind-bad */\n"
    assert_nil rank(bad)
    assert_equal @original, File.read(@path)
  end

  def test_ties_go_to_the_smallest_diff
    small = ".a { margin: 16px; } /* kind-good */\n"
    big = ".a { margin: 16px; }\n.b { margin: 16px; }\n.c { margin: 16px; } /* kind-good */\n"
    assert_equal small, rank(big, small)
  end

  def test_empty_unchanged_and_duplicate_candidates_are_ignored
    assert_nil rank("", @original, "  ")
  end

  def test_unrenderable_candidates_are_discarded
    none = ->(_s, root:) { [] }
    assert_nil B.rank([".a{}"], original: @original, surfaces: [@surface], root: @root, measurer: none, read:, write:, rebuild:)
  end

  def test_failed_navigation_is_not_a_candidate
    bad = ->(_surfaces, root:) { [[@surface, rendering("good").merge("status" => 503)]] }
    assert_nil B.rank([".a{}"], original: @original, surfaces: [@surface], root: @root, measurer: bad, read:, write:, rebuild:)
    assert_equal @original, File.read(@path)
  end

  def test_rescore_requires_every_requested_surface_before_and_after
    render = Master::Fix::LayoutScoreRender
    other = Surface.new("brgen/home/desktop", "desktop")
    good = rendering("good")
    complete = [[@surface, good], [other, good]]
    [
      [complete, complete, true],
      [[complete.first], complete, false],
      [complete, [complete.first], false],
      [complete, [[@surface, good], [other, good.merge("error" => "timeout")]], false],
    ].each do |before, after, expected|
      samples = [before, after]
      measure = ->(_surfaces, root:) { samples.shift }
      hook = render.rescore_hook([@surface, other], root: @root, measurer: measure)
      assert_equal expected, hook.call(@path)
    end
  end

  def test_duplicate_surface_captures_are_not_scored
    render = Master::Fix::LayoutScoreRender
    other = Surface.new("brgen/home/desktop", "desktop")
    good = rendering("good")

    assert_equal [other.id], render.scores([[@surface, good], [@surface, good], [other, good]], root: @root).keys
  end

  def test_failed_and_empty_payloads_do_not_enter_the_score
    render = Master::Fix::LayoutScoreRender
    good = rendering("good")
    [nil, good.merge("error" => "timeout"), good.merge("status" => 404),
     good.merge("vw" => 0), good.merge("elements" => [])].each do |bad|
      assert_empty render.scores([[@surface, bad]], root: @root)
    end
  end

  def test_concurrent_source_change_during_render_is_preserved
    good = ".a { margin: 16px; } /* kind-good */\n"
    concurrent = ".a { margin: 21px; } /* another writer */\n"
    measurer = lambda do |_surfaces, root:|
      File.write(@path, concurrent)
      [[@surface, rendering("good")]]
    end

    error = assert_raises(B::SourceChanged) do
      B.rank([good], original: @original, surfaces: [@surface], root: @root,
             measurer:, read:, write:, rebuild:)
    end

    assert_match(/concurrent content was preserved/, error.message)
    assert_equal concurrent, File.read(@path)
  end

  def test_each_candidate_and_original_are_rebuilt
    good = ".a { margin: 16px; } /* kind-good */\n"
    mid = ".a { margin: 12px; } /* kind-mid */\n"
    builds = []
    build = -> { builds << File.read(@path); true }
    measure = ->(_surfaces, root:) do
      assert_equal builds.last, File.read(@path)
      measurer.call([@surface], root:)
    end

    assert_equal good, B.rank([mid, good], original: @original, surfaces: [@surface], root: @root,
                              measurer: measure, read:, write:, rebuild: build)
    assert_equal [mid, @original, good, @original], builds
  end

  def test_failed_candidate_build_is_never_rendered
    build = -> { File.read(@path) == @original }
    measure = ->(*) { flunk "failed build must not be rendered" }

    assert_nil B.rank([".a{}"], original: @original, surfaces: [@surface], root: @root,
                       measurer: measure, read:, write:, rebuild: build)
    assert_equal @original, File.read(@path)
  end

  def test_failed_original_build_refuses_the_candidate
    build = -> { File.read(@path) != @original }

    assert_raises(B::RestoreFailed) do
      B.rank([".a{}"], original: @original, surfaces: [@surface], root: @root,
             measurer:, read:, write:, rebuild: build)
    end
    assert_equal @original, File.read(@path)
  end

  def test_concurrent_candidate_before_trial_is_not_overwritten
    candidate = ".a{}"
    File.write(@path, candidate)

    assert_raises(B::SourceChanged) do
      rank(candidate)
    end
    assert_equal candidate, File.read(@path)
  end

  def test_synthesis_retains_alternatives_and_stops_on_repeated_revision
    calls = []
    refine = lambda do |selected, critique|
      calls << [selected, critique]
      "combined"
    end
    rows = B.synthesize_candidates(%w[first second], preferred_count: 2, critique: "review",
      refine:) { |row| row }
    assert_equal %w[combined first second], rows
    assert_equal 2, calls.size
    assert_includes calls.first.last, "second"
  end

  def test_synthesis_does_not_exceed_candidate_ceiling
    rows = Array.new(B::MAX_N) { |i| i.to_s }
    assert_equal rows, B.synthesize_candidates(rows, preferred_count: 2, critique: "review",
      refine: ->(*) { flunk "full pool must not grow" }) { |row| row }
  end

  def test_identical_edits_at_different_locations_remain_distinct
    original = "same\nkeep\nsame\n"
    first = "changed\nkeep\nsame\n"
    second = "same\nkeep\nchanged\n"
    refute_equal B.change_signature(original, first), B.change_signature(original, second)
  end

  def test_change_signature_retains_source_lines_starting_with_diff_markers
    assert B.change_signature("++ old\n", "++ new\n").any? { |line| line.include?("new") }
  end

  def test_diversity_compares_changed_lines_not_the_unchanged_file
    original = "a\nb\nc\n"
    variants = ["a\nnew value\nc\n", "a\nnew  value\nc\n", "a\nb\nother\n"]
    distinct = B.distinct_changes(variants) { |source| B.change_signature(original, source) }
    assert_equal [variants.first, variants.last], distinct
  end

  def test_candidate_coverage_uses_distinct_diffs_not_generated_count
    partial = B.diversity_receipt(requested: 10, generated: 10, distinct: 3)
    assert_equal :partial, partial.fetch(:status)
    assert_equal :normalized_diff, partial.fetch(:method)
    assert_equal 3, partial.fetch(:distinct)

    complete = B.diversity_receipt(requested: 10, generated: 12, distinct: 10)
    assert_equal :observed, complete.fetch(:status)
  end

  def test_visual_exploration_defaults_to_ten_and_clamps_to_fifty
    ENV.delete("MASTER_FIX_BEST_OF")
    assert_equal 10, B.n
    ENV["MASTER_FIX_BEST_OF"] = "1"
    assert_equal 10, B.n
    ENV["MASTER_FIX_BEST_OF"] = "100"
    assert_equal 50, B.n
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end

  def test_missing_surface_rejects_candidate
    other = Surface.new("brgen/home/desktop", "desktop")
    assert_nil B.rank([".a{}"], original: @original, surfaces: [@surface, other], root: @root, measurer:, read:, write:, rebuild:)
  end

  def test_active_only_for_visual_style_findings_with_n_above_one
    ENV["MASTER_FIX_BEST_OF"] = "3"
    assert_equal 10, B.n
    assert B.active?({ law: B::LAW_ID, file: "x.scss" }, Object.new)
    refute B.active?({ law: "OTHER", file: "x.scss" }, Object.new)
    refute B.active?({ law: B::LAW_ID, file: "x.erb" }, Object.new)
    refute B.active?({ law: B::LAW_ID, file: "x.scss" }, nil)
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end

  class FakeLoop
    def initialize(replies, models: []) = (@replies = replies; @models = models; @visual_image = nil)
    def build_prompt_for(violation:, src:, path:) = "fix #{path}"
    def ask_agent(_prompt, image: nil)
      Thread.current[:master_llm_answer_model] = @models.shift
      @replies.shift
    end
    def extract_code(text, _ext) = text
    def write_atomic(path, src) = File.write(path, src)
  end

  def test_pick_asks_for_n_minus_one_more_and_returns_the_winner
    ENV["MASTER_FIX_BEST_OF"] = "3"
    custody = Struct.new(:surfaces).new([@surface])
    good = ".a { margin: 16px; } /* kind-good */\n"
    loop = FakeLoop.new([".a { margin: 3px; } /* kind-bad */\n", good])
    violation = { law: B::LAW_ID, file: @path }
    first = ".a { margin: 12px; } /* kind-mid */\n"
    assert_equal good, B.pick(loop, violation, first, custody:, root: @root, measurer:, rebuild:)
    assert_equal @original, File.read(@path)
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
  end
  def test_pick_tracks_the_writer_of_the_visual_winner
    ENV["MASTER_FIX_BEST_OF"] = "3"
    custody = Struct.new(:surfaces).new([@surface])
    bad = ".a { margin: 3px; } /* kind-bad */\n"
    good = ".a { margin: 16px; } /* kind-good */\n"
    loop = FakeLoop.new([bad, good], models: ["grok-cli:auto", "moonshotai/kimi-k2"])
    Thread.current[:master_fix_candidate_author_models] = ["anthropic/claude-opus-5-5"]

    assert_equal good, B.pick(loop, { law: B::LAW_ID, file: @path },
                              ".a { margin: 12px; } /* kind-mid */\n", custody:, root: @root, measurer:, rebuild:)
    assert_equal ["anthropic/claude-opus-5-5", "moonshotai/kimi-k2"],
                 Thread.current[:master_fix_candidate_author_models]
  ensure
    ENV.delete("MASTER_FIX_BEST_OF")
    Thread.current[:master_fix_candidate_author_models] = nil
    Thread.current[:master_llm_answer_model] = nil
  end
end

class TestUserSimulation < Minitest::Test
  UserSimulation = Master::Fix::UserSimulation
  CAMPAIGN = File.join(Master::REPO_ROOT, "RAILS", "test", "interaction_campaign_400.json")

  def test_simulator_reuses_the_existing_candidate_owner_file
    owner = File.join(Master::REPO_ROOT, "MASTER", "lib", "fix", "best_of_n.rb")
    strategy = File.join(Master::REPO_ROOT, "MASTER", "lib", "fix", "repair_loop", "fix_strategies.rb")
    standalone = File.join(Master::REPO_ROOT, "MASTER", "lib", "fix", "user_simulation.rb")

    assert File.file?(owner)
    assert_includes File.read(owner), "class UserSimulation"
    assert_includes File.read(strategy), 'require_relative "../best_of_n"'
    refute File.exist?(standalone), "the simulator must not create a second implementation file"
  end

  def test_campaign_schema_and_runtime_evidence_are_validated
    campaign = JSON.parse(File.read(CAMPAIGN, encoding: "UTF-8"))

    assert_equal 400, campaign.fetch("cases").length
    assert_equal 20, campaign.fetch("surfaces").length
    assert_equal 20, campaign.fetch("fault_modes").length
    assert_equal 400, campaign.fetch("cases").map { |row| row.fetch("id") }.uniq.length

    campaign.fetch("cases").each do |row|
      assert_includes UserSimulation::RUNTIME_STATES, row.fetch("runtime_status")
      if %w[PASS FAIL].include?(row.fetch("runtime_status"))
        refute_empty row.fetch("runtime_evidence").to_s, "#{row.fetch("id")} requires runtime evidence"
      end
    end
  end

  def test_every_focused_test_mapping_points_to_a_real_test_file
    surfaces = JSON.parse(File.read(CAMPAIGN, encoding: "UTF-8")).fetch("surfaces")

    surfaces.each do |surface|
      name = surface.fetch("id")
      paths = surface.fetch("focused_test_paths")
      refute_empty paths, "#{name} has no focused test mapping"
      assert_equal paths.length, paths.uniq.length, "#{name} repeats a test path"

      paths.each do |relative|
        refute relative.start_with?("/"), "#{name}: absolute test path #{relative}"
        refute relative.split("/").include?(".."), "#{name}: test path escapes the repository"
        assert File.file?(File.join(Master::REPO_ROOT, relative)),
               "#{name}: focused test path is missing: #{relative}"
      end

      assert_equal paths, UserSimulation.new(root: Master::REPO_ROOT, campaign_path: CAMPAIGN).focused_test_paths_for(name),
                   "#{name}: runtime resolver diverged from the campaign manifest"
    end
  end

  def test_relevant_user_scenarios_are_prompted_as_oracles_not_results
    simulation = UserSimulation.new(root: Master::REPO_ROOT)
    path = File.join(Master::REPO_ROOT, "RAILS", "brgen", "app", "controllers", "posts_controller.rb")

    context = simulation.scenario_context(path:)

    assert_includes context, "USER-SIMULATION ORACLES"
    assert_includes context, "RI-021"
    assert_includes context, "not an executed test"
    assert_includes context, "inventory_state=NOT_RUN"
  end

  def test_candidate_approaches_are_materially_distinct_and_bounded
    approaches = (0...10).map { |index| UserSimulation.approach(index) }

    assert_equal 10, approaches.map { |row| row.fetch(:name) }.uniq.length
    assert_equal 10, approaches.map { |row| row.fetch(:instruction) }.uniq.length
    assert_operator UserSimulation.candidate_count, :>=, 10
    assert_operator UserSimulation.candidate_count, :<=, 50
  end

  def test_candidate_telemetry_does_not_claim_scenario_execution
    Dir.mktmpdir("master-campaign-telemetry") do |root|
      path, tests = fixture_tree(root, "broken\n")
      events = []
      bus = Object.new
      bus.define_singleton_method(:publish) { |event, payload = {}| events << [event, payload] }
      runner = ->(_test_path) { { state: :pass, signature: "pass" } }
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:, bus:)
      writer = ->(target, source) { File.write(target, source) }

      result = simulation.evaluate_candidates(
        path:, original: "broken\n", candidates: ["fixed\n"], writer:,
      ).fetch(0)

      assert_equal :pass, result.fetch(:status)
      _event, payload = events.find { |event, _| event == "repair_loop:candidate_simulation" }
      assert_equal tests, payload.fetch(:tests)
      assert_equal 20, payload.fetch(:scenario_oracles_consulted)
      assert_equal "NOT_RUN", payload.fetch(:scenario_runtime_status)
      refute payload.key?(:scenarios), "oracle count must not imply executed journeys"
    end
  end

  def test_passing_candidate_is_tested_and_original_source_is_restored
    Dir.mktmpdir("master-user-simulation") do |root|
      path, tests = fixture_tree(root, "broken\n")
      runner = lambda do |_test_path|
        File.read(path).strip == "fixed" ?
          { state: :pass, signature: "pass" } :
          { state: :fail, signature: "baseline-failure" }
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      results = simulation.evaluate_candidates(
        path:, original: "broken\n", candidates: ["fixed\n"], writer:,
      )

      assert_equal :pass, results.fetch(0).fetch(:status)
      assert_equal tests.sort, results.fetch(0).fetch(:test_paths).sort
      assert_equal "broken\n", File.read(path)
    end
  end

  def test_candidate_introducing_failure_is_rejected_and_source_is_restored
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = lambda do |_test_path|
        if File.read(path).strip == "safe"
          { state: :pass, signature: "pass" }
        else
          { state: :fail, signature: "new-failure" }
        end
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["broken\n"], writer:,
      ).fetch(0)

      assert_equal :regression, result.fetch(:status)
      refute_empty result.fetch(:regressions)
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_unavailable_runner_is_blocked_not_passed
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = ->(_test_path) { { state: :blocked, signature: "browser-unavailable", detail: "browser unavailable" } }
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["fixed\n"], writer:,
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      refute_equal :pass, result.fetch(:status)
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_candidate_simulation_never_overwrites_concurrent_source_changes
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = lambda do |_test_path|
        File.write(path, "concurrent edit\n") if File.read(path).strip == "candidate"
        { state: :pass, signature: "pass" }
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      error = assert_raises(UserSimulation::RestoreFailure) do
        simulation.evaluate_candidates(
          path:, original: "safe\n", candidates: ["candidate\n"], writer:,
        )
      end

      assert_match(/refusing to overwrite concurrent content/, error.message)
      assert_equal "concurrent edit\n", File.read(path)
    end
  end

  def test_symlinked_target_is_blocked_without_writing_through_the_link
    Dir.mktmpdir("master-user-simulation") do |root|
      outside = File.join(root, "outside.rb")
      File.write(outside, "outside original\n")
      path = File.join(root, "RAILS", "brgen", "app", "models", "post.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.symlink(outside, path)
      write_called = false
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN)
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "outside original\n", candidates: ["candidate\n"], writer:,
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      refute write_called
      assert File.symlink?(path)
      assert_equal "outside original\n", File.read(outside)
    end
  end

  def test_insufficient_file_budget_blocks_before_touching_source
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      write_called = false
      simulation = UserSimulation.new(
        root:, campaign_path: CAMPAIGN,
        deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      )
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["candidate\n"], writer:,
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      assert_match(/file budget cannot reserve/, result.fetch(:reason))
      refute write_called
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_missing_test_mapping_is_explicit_and_does_not_write_a_candidate
    Dir.mktmpdir("master-user-simulation") do |root|
      path = File.join(root, "misc", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "original\n")
      write_called = false
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN)
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "original\n", candidates: ["candidate\n"], writer:,
      ).fetch(0)

      assert_equal :unavailable, result.fetch(:status)
      refute write_called, "no candidate source should be changed when there is no focused test"
      assert_equal "original\n", File.read(path)
    end
  end

  private

  def fixture_tree(root, source)
    path = File.join(root, "RAILS", "brgen", "app", "models", "post.rb")
    tests = UserSimulation.new(root:, campaign_path: CAMPAIGN).focused_test_paths_for("brgen_social")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    tests.each do |test_path|
      absolute = File.join(root, test_path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "# isolated fake test path\n")
    end
    [path, tests]
  end
end
