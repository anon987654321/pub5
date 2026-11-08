# frozen_string_literal: true

require_relative "test_helper"
require "fix/conversation_probe"
require "yaml"
require "tmpdir"

# The conversation stage measures the CLI the way the operator meets it. The
# deterministic suite must pass on the real corpus without a model, and the
# known-bad fixtures here must each be caught, because a probe that passes while
# measuring nothing is worse than one that errors.
class TestConversationProbe < Minitest::Test
  Probe = Master::Fix::ConversationProbe
  Rubric = Master::Voice::DialogueRubric

  def test_deterministic_suite_passes_on_the_real_corpus_without_a_model
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: false)

    assert_equal "PASS", report.deterministic[:status]
    assert_equal "SKIPPED", report.live[:status]
    assert_empty report.findings
    names = report.deterministic[:checks].map { |check| check[:name] }
    assert_equal %w[corpus routing instrument prompt_reach], names
  end

  def test_corpus_has_all_three_intents_and_unique_ids
    scenarios = Rubric.ux_scenarios

    assert scenarios.size >= 6, "the corpus must cover the surfaces it probes"
    assert_equal scenarios.map { |row| row["id"] }, scenarios.map { |row| row["id"] }.uniq
    assert_includes Probe::SCENARIO_INTENTS, "day_to_day"
    (Probe::SCENARIO_INTENTS - %w[support]).each do |intent|
      assert scenarios.any? { |row| row["intent"] == intent }, "corpus must contain #{intent} scenarios"
    end
  end

  # Verify the instrument against a case whose answer is already known: a reply
  # that opens with a forbidden opener must fail, not pass.
  def test_live_reply_with_a_forbidden_opener_fails_and_names_the_corpus
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 1,
                       spawner: ->(_turn) { { status: :ok, output: "master0: ready\nAs an AI language model, I hope this helps!" } })

    row = report.live[:cases].first
    assert_equal :fail, row[:status]
    assert_match(/no_ai_isms/, row[:reason])
    finding = report.findings.find { |item| item[:message].include?("live") }
    assert_equal Probe::RUBRIC_DATA, finding[:file]
    assert_equal :warning, finding[:severity]
  end

  def test_live_reply_within_the_bench_passes
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 1,
                       spawner: ->(_turn) { { status: :ok, output: "\e[32mmaster0: ready\e[0m\nChecked the disk: root is at 41 percent, nothing close to full." } })

    row = report.live[:cases].first
    assert_equal :pass, row[:status]
    assert row[:seconds].is_a?(Numeric)
    assert_empty report.findings
  end

  def test_a_degraded_lane_is_inconclusive_never_a_pass
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 1,
                       spawner: ->(_turn) { { status: :ok, output: "master0: ready\nno model is available, the reply was not generated" } })

    assert_equal :inconclusive, report.live[:cases].first[:status]
    assert_equal "INCONCLUSIVE", report.live[:status]
    assert_equal "INCONCLUSIVE", report.status
    assert_empty report.findings, "an inconclusive case names no finding"
  end

  def test_a_dead_surface_is_inconclusive_never_a_pass
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 1,
                       spawner: ->(_turn) { { status: :unavailable, message: "PTY unavailable: Errno::ENOENT" } })

    assert_equal :inconclusive, report.live[:cases].first[:status]
    assert_match(/PTY unavailable/, report.live[:cases].first[:reason])
  end

  def test_an_unextractable_reply_is_inconclusive
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 1,
                       spawner: ->(_turn) { { status: :ok, output: "master0: ready\n\nboot0 at mainbus0: safe 1" } })

    assert_equal :inconclusive, report.live[:cases].first[:status]
    assert_match(/not extractable/, report.live[:cases].first[:reason])
  end

  def test_the_agent_lane_answers_without_a_terminal
    agent = Struct.new(:reply).new("Checked the disk; nothing is close to full.")
    def agent.ask_once(_turn, **_options) = reply

    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 1, agent:, spawner: nil)

    assert_equal :pass, report.live[:cases].first[:status]
  end

  def test_zero_budget_skips_the_live_suite
    report = Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 0)

    assert_equal "SKIPPED", report.live[:status]
    assert_match(/MASTER_FIX_CONVERSATION_MAX=0/, report.live[:reason])
    assert_equal "PASS", report.status, "the deterministic half still proves what it measured"
  end

  def test_max_live_bounds_the_asked_cases
    cases_run = []
    Probe.run(root: Master::ROOT, target: "MASTER", live: true, max_live: 2,
              spawner: ->(turn) { cases_run << turn; { status: :ok, output: "master0: ready\nA short, plain reply." } })

    assert_equal 2, cases_run.size
  end

  def test_extract_reply_strips_ansi_and_instrument_lines
    text = "\e[1mmaster0: ready\e[0m\nboot0 at mainbus0: safe 1\nThe answer is forty-two."
    assert_equal "The answer is forty-two.", Probe.extract_reply(text)
    assert_nil Probe.extract_reply("master0: ready\n\n")
  end

  # A misrouted corpus must fail the routing check against a real rubric copy,
  # because a green routing check must mean the expectations were actually read.
  # The corpus stays whole: only one scenario's intent flips, so the validator
  # still accepts the data and the failure is the routing one, nothing else.
  def test_routing_misroute_is_caught_against_a_real_rubric_copy
    Dir.mktmpdir do |dir|
      master_root = File.join(dir, "MASTER")
      write_rubric_variant(master_root) do |payload|
        scenario = payload["ux_probe"]["scenarios"].find { |row| row["id"] == "disk_check" }
        scenario["intent"] = "chitchat"
        payload
      end
      report = Probe.run(root: master_root, target: "MASTER", live: false)

      assert_equal "FAIL", report.deterministic[:status]
      finding = report.findings.find { |item| item[:message].include?("routing") }
      assert_equal Probe::ROUTER_RUBY, finding[:file]
      assert_match(/disk_check/, finding[:message])
    end
  end

  def test_support_misroute_names_the_rubric_not_the_router
    Dir.mktmpdir do |dir|
      master_root = File.join(dir, "MASTER")
      write_rubric_variant(master_root) do |payload|
        scenario = payload["ux_probe"]["scenarios"].find { |row| row["id"] == "sleep_anxiety" }
        scenario["user"] = "Run the nightly backup on vm23 tonight."
        payload
      end
      report = Probe.run(root: master_root, target: "MASTER", live: false)

      finding = report.findings.find { |item| item[:message].include?("routing") }
      assert_equal Probe::RUBRIC_RUBY, finding[:file]
    end
  end

  def test_a_count_drift_copy_is_not_valid
    Dir.mktmpdir do |dir|
      master_root = File.join(dir, "MASTER")
      write_rubric_variant(master_root) do |payload|
        payload["bench"]["ux_probe_scenario_count"] = 99
        payload
      end

      refute Rubric.valid?(root: master_root), "the bench count must agree with the corpus"
    end
  end

  # The PTY leg is a real boot, so it runs only when the operator asks for it;
  # the default suite stays deterministic and offline.
  def test_pty_wire_check_against_the_real_cli
    skip "set MASTER_CONVERSATION_PTY_SMOKE=1 to boot the real CLI in a PTY" unless ENV["MASTER_CONVERSATION_PTY_SMOKE"] == "1"

    result = Probe.pty_turn("hello, what can you do?", root: Master::ROOT)
    assert_equal :ok, result[:status], result[:message].to_s
    refute_empty Probe.extract_reply(result[:output]).to_s
  end

  private

  # A copy of the real rubric with one block rewritten, so the suite exercises the
  # real validator against real data instead of inventing a second fixture shape.
  def write_rubric_variant(master_root)
    require "fileutils"
    FileUtils.mkdir_p(File.join(master_root, "data"))
    payload = YAML.safe_load_file(File.join(Master::ROOT, "data", "dialogue_rubric.yml"), aliases: true)
    payload = yield payload
    File.write(File.join(master_root, "data", "dialogue_rubric.yml"), YAML.dump(payload))
    master_root
  end
end
