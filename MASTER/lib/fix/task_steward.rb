# frozen_string_literal: true

require "time"
require_relative "constants"
require_relative "../ground/failure_taxonomy"

module Master
  module Fix
    # Keeps unfinished conversational missions alive after an individual fold
    # attempt ends. The mission is the durable objective; this steward wakes a bounded fold or
    # backlog runner again only when the persisted record says it is due.
    class TaskSteward
      POLL_SECONDS = Integer(ENV.fetch("MASTER_TASK_POLL_SECONDS", "15")).clamp(1, 300)

      class << self
        def start!(root:, bus: nil, runner:, after_run: nil)
          return if ENV["MASTER_TASK_STEWARD"] == "0"

          @mutex ||= Mutex.new
          @instances ||= {}
          key = File.expand_path(root)
          @mutex.synchronize do
            current = @instances[key]
            return current if current&.alive?

            steward = new(root:, bus:, runner:, after_run:)
            @instances[key] = steward.start!
          end
        end

        def wake(root: Master::ROOT)
          instance = @instances&.fetch(File.expand_path(root), nil)
          instance&.wake!
        rescue StandardError
          nil
        end
      end

      def initialize(root:, bus:, runner:, after_run: nil)
        @root = File.expand_path(root)
        @bus = bus
        @runner = runner
        @after_run = after_run
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @stop = false
        @wake_requested = false
        @thread = nil
      end

      def start!
        return self if alive?

        @stop = false
        @thread = Thread.new { run_forever }
        @thread.abort_on_exception = false
        self
      end

      def stop!
        @mutex.synchronize do
          @stop = true
          @condition.broadcast
        end
        @thread&.join(2)
        @thread&.kill if @thread&.alive?
        @thread = nil
        self
      end

      def alive? = @thread&.alive? || false

      def wake!
        @mutex.synchronize do
          @wake_requested = true
          @condition.broadcast
        end
        self
      end

      def tick!
        record = Mission.current(root: @root)
        unless eligible?(record)
          # A future-due backlog mission may be parked while independent work
          # advances. Do not reinterpret an explicitly disabled or non-backlog
          # mission as permission to enqueue unattended repository work.
          if record && record["origin"].to_s == "backlog" &&
             record["auto_continue"] == true && record["state"].to_s == "waiting"
            notify_after_run(:idle)
          end
          return :idle
        end

        if continuation_only?(record)
          reason = "auto-continue blocked: #{record["goal"].to_s.inspect} is a continuation, not a durable task; submit the resolved objective"
          blocked = Mission.new(root: @root, bus: @bus).block_if_unleased!(id: record["id"], reason:)
          return :idle unless blocked

          @bus&.publish("task_steward:blocked", mission: record["id"], reason:)
          result = Master::Result.err(reason, category: :validation)
          notify_after_run(result)
          return result
        end

        goal = record["goal"].to_s
        @bus&.publish("task_steward:run", mission: record["id"], goal:, attempt: record["attempt_count"].to_i + 1)
        result = Master::Trace::WorkerReceipt.around(@bus, worker: "task_steward", job: "mission #{record["id"]}") do
          @runner.call(goal:, mission: record)
        end
        recover_failed_result(result)
        ok = result_ok?(result)
        @bus&.publish("task_steward:result", mission: record["id"], ok:)
        notify_after_run(result)
        result
      rescue StandardError => e
        defer_failed_mission(e)
        @bus&.publish("task_steward:error", error: "#{e.class}: #{e.message}")
        result = Master::Result.err("task steward: #{e.message}", category: :infrastructure)
        notify_after_run(result)
        result
      end

      private

      def run_forever
        loop do
          break if stopped?

          tick!
          wait_for_wake
        rescue StandardError => e
          @bus&.publish("task_steward:loop_error", error: "#{e.class}: #{e.message}")
          wait_for_wake
        end
        @bus&.publish("task_steward:stop")
      end

      # Continuation needs the live conversation; a background worker cannot reconstruct it.
      CONTEXTLESS_GOALS = ["do it", "lets do it"].freeze

      def continuation_only?(record)
        goal = record["goal"].to_s.downcase.strip.split.join(" ")
        goal = goal[0...-1] while %w[! . ? ...].include?(goal[-1])
        intent = record.dig("operator", "intent").to_s
        intent == "continue_prior_plan" || CONTEXTLESS_GOALS.include?(goal.delete("'"))
      end

      def eligible?(record)
        return false unless record
        return false unless %w[fold backlog].include?(record["origin"].to_s)
        return false unless record["auto_continue"] == true
        return false unless %w[running waiting].include?(record["state"].to_s)

        due?(record)
      end

      def due?(record)
        return true if record["state"].to_s == "running" && lease_expired?(record)
        return false unless record["state"].to_s == "waiting"

        wake = record["next_wake_at"]
        return true if wake.to_s.empty?

        Time.iso8601(wake.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def lease_expired?(record)
        wake = record["lease_until"]
        return true if wake.to_s.empty?

        Time.iso8601(wake.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def wait_for_wake
        seconds = wait_seconds
        @mutex.synchronize do
          return if @stop

          @condition.wait(@mutex, seconds) unless @wake_requested
          @wake_requested = false
        end
      end

      def wait_seconds
        record = Mission.current(root: @root)
        return POLL_SECONDS unless record && %w[fold backlog].include?(record["origin"].to_s) && record["auto_continue"] == true
        return 0 if record["state"].to_s == "waiting" && due?(record)

        if record["state"].to_s == "waiting"
          wake = record["next_wake_at"].to_s
          return POLL_SECONDS if wake.empty?

          [Time.iso8601(wake) - Time.now.utc, POLL_SECONDS].min.clamp(0, POLL_SECONDS)
        else
          POLL_SECONDS
        end
      rescue ArgumentError
        # An unreadable wake time reads as due; waiting zero re-ran the mission without pause.
        POLL_SECONDS
      end

      def defer_failed_mission(error)
        record = Mission.current(root: @root)
        settle_mission_failure(record, "#{error.class}: #{error.message}")
      rescue StandardError => e
        @bus&.publish("task_steward:defer_error", error: "#{e.class}: #{e.message}")
      end

      def recover_failed_result(result)
        return unless result.respond_to?(:err?) && result.err?

        record = Mission.current(root: @root)
        return unless record && record["state"].to_s == "running"

        settle_mission_failure(record, result.message.to_s)
      rescue StandardError => e
        @bus&.publish("task_steward:result_recovery_error", error: "#{e.class}: #{e.message}")
      end

      def settle_mission_failure(record, message)
        return unless record && %w[fold backlog].include?(record["origin"].to_s)
        return unless record["auto_continue"] == true && record["state"].to_s == "running"
        return if leased_by_another_process?(record)

        category = Master::Ground::FailureTaxonomy.shared.classify(message)
        reason = "#{category}: #{message}"
        mission = Mission.new(root: @root, bus: @bus)
        case category
        when :transient
          mission.defer!(reason:)
        when :exhausted
          mission.defer!(reason:, seconds: Mission::RETRY_MAX_SECONDS)
        when :permanent
          mission.fail!(reason)
        else
          mission.block!(reason: "human review required: #{reason}")
        end
        @bus&.publish("task_steward:failure_classified", mission: record["id"], category:)
      end

      def notify_after_run(result)
        @after_run&.call(mission: Mission.current(root: @root), result:)
      rescue StandardError => e
        @bus&.publish("task_steward:after_run_error", error: "#{e.class}: #{e.message}")
      end

      def leased_by_another_process?(record)
        return false unless record["state"].to_s == "running"

        owner = record["lease_owner"].to_s
        return false if owner.empty? || owner == Mission.instance_id

        !lease_expired?(record)
      end

      def result_ok?(result)
        return result.ok? if result.respond_to?(:ok?)

        result.is_a?(Hash) && result[:reason].to_sym == :complete
      rescue StandardError
        false
      end

      def stopped?
        @mutex.synchronize { @stop }
      end
    end
  end
end
