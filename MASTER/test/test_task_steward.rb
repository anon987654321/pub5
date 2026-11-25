# frozen_string_literal: true

require_relative "test_helper"
require "fix/task_steward"
require "tmpdir"

class TaskStewardTest < Minitest::Test
  def write_mission(root, next_wake_at: Time.now.utc.iso8601, auto_continue: true, origin: "fold",
                   goal: "finish the task", intent: nil)
    mission = Master::Fix::Mission.new(root:)
    mission.start!(goal:, scope: root, origin:, auto_continue:)
    mission.send(:with_lock) do
      record = mission.instance_variable_get(:@record)
      record["operator"]["intent"] = intent if intent
      record["state"] = "waiting"
      record["next_wake_at"] = next_wake_at
      record["lease_owner"] = nil
      record["lease_until"] = nil
      mission.send(:persist!)
    end
    mission
  end

  def test_tick_reenters_due_fold_mission
    Dir.mktmpdir do |root|
      mission = write_mission(root)
      calls = []
      steward = Master::Fix::TaskSteward.new(
        root:,
        bus: nil,
        runner: ->(goal:, mission:) { calls << [goal, mission["id"]]; :continued },
      )

      assert_equal :continued, steward.tick!
      assert_equal [[mission.record["goal"], mission.id]], calls
    end
  end

  def test_backlog_origin_is_eligible_for_the_existing_steward
    Dir.mktmpdir do |root|
      write_mission(root, origin: "backlog")
      calls = []
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil,
        runner: ->(goal:, mission:) { calls << mission["origin"]; :continued },
      )

      assert_equal :continued, steward.tick!
      assert_equal ["backlog"], calls
    end
  end

  def test_after_run_receives_the_terminal_backlog_mission
    Dir.mktmpdir do |root|
      write_mission(root, origin: "backlog")
      observed = nil
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil,
        runner: ->(**) {
          Master::Fix::Mission.new(root:).finish!(state: "completed", summary: "focused proof passed")
          Master::Result.ok(:continued)
        },
        after_run: ->(mission:, result:) { observed = mission },
      )

      result = steward.tick!
      assert result.ok?
      assert_equal :continued, result.value!
      assert_equal "completed", observed.fetch("state")
      assert_equal "deliver", observed.fetch("stage")
      assert_equal "backlog", observed.fetch("origin")
    end
  end

  def test_non_fold_missions_are_invisible
    Dir.mktmpdir do |root|
      write_mission(root, origin: "fix")
      calls = []
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { calls << true })
      assert_equal :idle, steward.tick!
      assert_empty calls
    end
  end

  def test_disabled_auto_continue_is_not_reentered
    Dir.mktmpdir do |root|
      write_mission(root, auto_continue: false)
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { flunk "should not run" })
      assert_equal :idle, steward.tick!
    end
  end

  def test_waiting_for_future_wake_is_not_reentered
    Dir.mktmpdir do |root|
      write_mission(root, next_wake_at: (Time.now.utc + 300).iso8601)
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { flunk "should not run" })
      assert_equal :idle, steward.tick!
    end
  end

  def test_future_backlog_mission_hands_off_to_independent_work
    Dir.mktmpdir do |root|
      mission = write_mission(
        root, origin: "backlog", next_wake_at: (Time.now.utc + 300).iso8601,
      )
      observed = nil
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { flunk "future mission must not run yet" },
        after_run: ->(mission:, result:) { observed = [mission, result] },
      )

      assert_equal :idle, steward.tick!
      assert_equal mission.id, observed.first.fetch("id")
      assert_equal "waiting", observed.first.fetch("state")
      assert_equal :idle, observed.last
    end
  end

  def test_terminal_backlog_handoff_retries_after_callback_failure
    %w[completed blocked failed].each do |state|
      record = { "id" => "first", "origin" => "backlog", "state" => state,
                 "auto_continue" => false }
      observed = []
      steward = Master::Fix::TaskSteward.new(
        root: Dir.tmpdir, bus: nil, runner: ->(**) { flunk "terminal task reran" },
        after_run: ->(mission:, result:) {
          observed << [mission.fetch("id"), result]
          raise "intake interrupted" if observed.one?
        },
      )
      Master::Fix::Mission.stub(:current, record) do
        2.times { assert_equal :idle, steward.tick! }
      end
      assert_equal [["first", :idle], ["first", :idle]], observed
    end
  end

  def test_terminal_foreground_mission_does_not_grant_backlog_intake
    record = { "id" => "manual", "origin" => "fold", "state" => "completed",
               "auto_continue" => false }
    steward = Master::Fix::TaskSteward.new(
      root: Dir.tmpdir, bus: nil, runner: ->(**) { flunk "terminal task reran" },
      after_run: ->(**) { flunk "foreground task granted backlog intake" },
    )
    Master::Fix::Mission.stub(:current, record) { assert_equal :idle, steward.tick! }
  end

  def test_disabled_backlog_mission_is_not_handed_off_to_unattended_intake
    Dir.mktmpdir do |root|
      write_mission(
        root, origin: "backlog", auto_continue: false,
        next_wake_at: (Time.now.utc + 300).iso8601,
      )
      callbacks = []
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { flunk "disabled mission must not run" },
        after_run: ->(**) { callbacks << true },
      )

      assert_equal :idle, steward.tick!
      assert_empty callbacks
    end
  end

  def test_expired_automatic_mission_is_reentered_after_many_attempts
    Dir.mktmpdir do |root|
      mission = write_mission(root, origin: "fold")
      mission.send(:with_lock) do
        record = mission.instance_variable_get(:@record)
        record["state"] = "running"
        record["attempt_count"] = 50
        record["lease_owner"] = nil
        record["lease_until"] = nil
        mission.send(:persist!)
      end

      calls = []
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { calls << true; :continued },
      )

      assert_equal :continued, steward.tick!
      assert_equal [true], calls
      assert_equal 50, Master::Fix::Mission.current(root:).fetch("attempt_count")
    end
  end

  def test_transient_failure_is_deferred_with_taxonomy_backoff
    Dir.mktmpdir do |root|
      write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { raise "provider overload" },
      )

      result = steward.tick!
      assert result.err?
      record = Master::Fix::Mission.current(root:)
      assert_equal "waiting", record.fetch("state")
      assert_equal true, record.fetch("auto_continue")
      assert_equal 1, record.fetch("retry_count")
      assert_operator Time.iso8601(record.fetch("next_wake_at")), :>, Time.now.utc
      assert_match(/transient:/, record.fetch("wake_reason"))
    end
  end

  def test_exhausted_provider_uses_long_reprobe_backoff
    Dir.mktmpdir do |root|
      write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { raise "insufficient credits" },
      )

      steward.tick!
      record = Master::Fix::Mission.current(root:)
      delay = Time.iso8601(record.fetch("next_wake_at")) - Time.now.utc
      assert_equal "waiting", record.fetch("state")
      assert_operator delay, :>, Master::Fix::Mission::RETRY_MAX_SECONDS - 3
      assert_operator delay, :<=, Master::Fix::Mission::RETRY_MAX_SECONDS
      assert_match(/exhausted:/, record.fetch("wake_reason"))
    end
  end

  def test_permanent_failure_fails_only_the_current_mission
    Dir.mktmpdir do |root|
      write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { raise "permission denied" },
      )

      steward.tick!
      record = Master::Fix::Mission.current(root:)
      assert_equal "failed", record.fetch("state")
      assert_equal false, record.fetch("auto_continue")
      assert_match(/permanent:/, record.fetch("error"))
      assert_match(/permanent:/, record.fetch("wake_reason"))
    end
  end

  def test_ambiguous_failure_requires_human_review
    Dir.mktmpdir do |root|
      write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil, runner: ->(**) { raise "partial write outcome unknown" },
      )

      steward.tick!
      record = Master::Fix::Mission.current(root:)
      assert_equal "blocked", record.fetch("state")
      assert_equal false, record.fetch("auto_continue")
      assert_match(/human review required/, record.fetch("wake_reason"))
    end
  end

  def test_returned_result_failure_is_classified_and_deferred
    Dir.mktmpdir do |root|
      mission = write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:, bus: nil,
        runner: ->(**) {
          current = Master::Fix::Mission.current(root:)
          Master::Fix::Mission.new(root:).start_or_resume!(
            goal: current.fetch("goal"), scope: root, origin: "fold", auto_continue: true,
          )
          Master::Result.err("provider overload", category: :infrastructure)
        },
      )

      result = steward.tick!
      assert result.err?
      record = Master::Fix::Mission.current(root:)
      assert_equal mission.id, record.fetch("id")
      assert_equal "waiting", record.fetch("state")
      assert_equal true, record.fetch("auto_continue")
      assert_equal 1, record.fetch("retry_count")
      assert_match(/transient:/, record.fetch("wake_reason"))
    end
  end

  def test_active_lease_failure_does_not_defer_another_process
    Dir.mktmpdir do |root|
      write_mission(root)
      steward = Master::Fix::TaskSteward.new(
        root:,
        bus: nil,
        runner: ->(**) {
          mission = Master::Fix::Mission.new(root:)
          current = Master::Fix::Mission.current(root:)
          mission.start_or_resume!(goal: current["goal"], scope: root)
          mission.send(:with_lock) do
            record = mission.instance_variable_get(:@record)
            record["lease_owner"] = "other-host:42"
            record["lease_until"] = (Time.now.utc + 300).iso8601
            mission.send(:persist!)
          end
          raise "runner collision"
        },
      )

      result = steward.tick!
      assert result.err?
      saved = Master::Fix::Mission.current(root:)
      assert_equal "running", saved["state"]
      assert_equal "other-host:42", saved["lease_owner"]
    end
  end

  def test_failed_runner_cannot_settle_a_replacement_mission
    initial = { "id" => "first", "origin" => "fold", "auto_continue" => true,
                "state" => "waiting", "goal" => "finish the task" }
    replacement = initial.merge("id" => "second", "state" => "running")
    [
      ->(**) { raise "provider overload" },
      ->(**) { Master::Result.err("provider overload", category: :infrastructure) },
    ].each do |runner|
      reads = 0
      current = ->(**) { reads += 1; reads == 1 ? initial : replacement }
      steward = Master::Fix::TaskSteward.new(root: Dir.tmpdir, bus: nil, runner:)
      Master::Fix::Mission.stub(:current, current) do
        steward.stub(:settle_mission_failure, ->(*) { flunk "replacement mission was settled" }) do
          assert steward.tick!.err?
        end
      end
    end
  end

  def test_after_run_does_not_receive_a_replacement_mission
    initial = { "id" => "first", "origin" => "backlog", "auto_continue" => true,
                "state" => "waiting", "goal" => "finish the task" }
    replacement = initial.merge("id" => "second", "state" => "running")

    [
      ->(**) { Master::Result.ok(:continued) },
      ->(**) { Master::Result.err("provider overload", category: :infrastructure) },
      ->(**) { raise "provider overload" },
    ].each do |runner|
      reads = 0
      current = ->(**) { reads += 1; reads == 1 ? initial : replacement }
      steward = Master::Fix::TaskSteward.new(
        root: Dir.tmpdir, bus: nil, runner:,
        after_run: ->(**) { flunk "a replacement mission received a stale result" },
      )
      Master::Fix::Mission.stub(:current, current) { steward.tick! }
      assert_operator reads, :>=, 2
    end
  end

  def test_waiting_mission_does_not_spin_on_due_or_invalid_wake_time
    record = { "id" => "first", "origin" => "fold", "auto_continue" => true, "state" => "waiting" }
    steward = Master::Fix::TaskSteward.new(root: Dir.tmpdir, bus: nil, runner: ->(**) {})
    ["", Time.now.utc.iso8601, "invalid"].each do |wake|
      Master::Fix::Mission.stub(:current, record.merge("next_wake_at" => wake)) do
        assert_operator steward.send(:wait_seconds), :>=, 1
      end
    end
  end

  def test_contextless_continuation_is_blocked_instead_of_replayed_forever
    Dir.mktmpdir do |root|
      write_mission(root, goal: "Let's do it!")
      calls = []
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { calls << true })

      result = steward.tick!

      assert result.err?
      assert_match(/continuation, not a durable task/, result.message)
      assert_empty calls
      saved = Master::Fix::Mission.current(root:)
      assert_equal "blocked", saved["state"]
      assert_match(/resolved objective/, saved["wake_reason"])
    end
  end

  def test_persisted_continuation_intent_is_not_replayed_without_context
    Dir.mktmpdir do |root|
      write_mission(root, goal: "continue the prior plan", intent: "continue_prior_plan")
      calls = []
      steward = Master::Fix::TaskSteward.new(root:, bus: nil, runner: ->(**) { calls << true })

      result = steward.tick!

      assert result.err?
      assert_empty calls
      assert_equal "blocked", Master::Fix::Mission.current(root:)["state"]
    end
  end

  def test_continuation_guard_does_not_block_a_mission_claimed_after_its_snapshot
    Dir.mktmpdir do |root|
      write_mission(root, goal: "Let's do it!")
      snapshot = Master::Fix::Mission.current(root:)
      claimant = Master::Fix::Mission.new(root:)
      claimant.start_or_resume!(goal: snapshot["goal"], scope: root, origin: "fold")

      blocked = Master::Fix::Mission.new(root:).block_if_unleased!(
        id: snapshot["id"], reason: "contextless continuation",
      )

      refute blocked
      saved = Master::Fix::Mission.current(root:)
      assert_equal "running", saved["state"]
      assert_equal Master::Fix::Mission.instance_id, saved["lease_owner"]
    end
  end

end
