# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # The run-state machine's entry points, re-opening the class defined in
      # fix/mission.rb: start!, ensure_queued! and start_or_resume!, plus the
      # unlocked record construction they share. Each entry holds the mission
      # lock for its whole read-decide-write leg, and the ordering between
      # reuse, supersede, interrupt and conflict refusal is load-bearing.
      def start!(goal:, scope: @root, model: nil, effort: "medium", plan: nil, origin: "unknown", auto_continue: false,
                 mode: "repair", risk: nil, intent: nil)
        with_lock do
          start_unlocked!(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
          persist!
        end
        emit("mission:start", @record.slice("id", "goal", "scope", "model", "effort"))
        self
      end

      # Prepare an objective without consuming an execution attempt. The background
      # supervisor uses this to create work that will be claimed only when due.
      def ensure_queued!(goal:, scope: @root, model: nil, effort: "medium", plan: nil, origin: "unknown", auto_continue: false, mode: "repair", risk: nil, intent: nil)
        with_lock do
          current = load_record
          reuse = queued_reuse_state(current, goal:, scope:)
          if reuse == :active
            @record = current
            @id = current["id"]
            return self
          end
          return self if reuse == :blocked

          raise active_mission_conflict(current, goal:, scope:) if active_for_other_target?(current, goal:, scope:)

          start_unlocked!(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
          queue_unlocked!
          persist!
        end
        emit("mission:queued", id: @id, goal: @record["goal"], scope: @record["scope"])
        self
      end

      # Reuse the durable objective when it is still alive. A completed mission
      # is deliberately a new objective on the next wake; a blocked mission may
      # be replaced only by an explicit/manual /fix request.
      def start_or_resume!(goal:, scope: @root, model: nil, effort: "medium", plan: nil, origin: "unknown", auto_continue: false,
                           mode: "repair", risk: nil, intent: nil)
        # resumed is read after with_lock returns; assignment inside the block
        # would be block-local and the emit below would see an unset local.
        resumed = false
        with_lock do
          current = load_record
          if reusable_for?(current, scope, goal)
            @record = current
            @id = current["id"]
            claim_unlocked!
            persist!
            resumed = true
          else
            restart_unlocked!(current, goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
          end
        end
        emit(resumed ? "mission:resume" : "mission:start", id: @id, goal: @record["goal"],
             scope: @record["scope"], attempt: @record["attempt_count"])
        self
      end

      private

      def manually_supersedable?(record, origin:)
        origin.to_s == "manual" && record && record["state"].to_s == "waiting" && record["lease_owner"].to_s.empty?
      end

      def supersede_waiting_unlocked!(record, goal:, scope:)
        @record = record
        @id = record["id"]
        @record["state"] = "interrupted"
        @record["stage"] = "deliver"
        @record["summary"] = "superseded by manual /fix for #{relative(scope)}".byteslice(0, MAX_GOAL_BYTES)
        @record["lease_owner"] = nil
        @record["lease_until"] = nil
        @record["next_wake_at"] = nil
        @record["finished_at"] = now
        @record["last_seen_at"] = now
        persist!
      end

      def reusable_for?(record, scope, goal)
        return false unless record
        return false unless RESUMABLE_STATES.include?(record["state"].to_s)
        return false unless record["goal"].to_s == goal.to_s
        return false unless record["scope"].to_s == relative(scope).to_s

        return true unless record["state"].to_s == "running"
        return true if record["lease_owner"].to_s == self.class.instance_id

        # A same-host process that no longer exists cannot renew or finish this
        # lease. Waiting for the five-minute expiry needlessly strands /fix after
        # SIGKILL; a live local or remote owner still holds the boundary.
        !mission_live?(record)
      end

      def active_for_other_target?(record, goal:, scope:)
        return false unless record
        return false unless RESUMABLE_STATES.include?(record["state"].to_s)

        return false unless mission_live?(record)
        return false if record["goal"].to_s == goal.to_s && record["scope"].to_s == relative(scope).to_s

        true
      end

      def same_process_mission?(record)
        record && record["lease_owner"].to_s == self.class.instance_id
      end

      def interrupt_for_next_target_unlocked!(record, goal:, scope:)
        @record = record
        @id = record["id"]
        @record["state"] = "interrupted"
        @record["stage"] = "deliver"
        @record["summary"] = "superseded by sequential /fix target #{relative(scope)}".byteslice(0, MAX_GOAL_BYTES)
        @record["lease_owner"] = nil
        @record["lease_until"] = nil
        @record["next_wake_at"] = nil
        @record["finished_at"] = now
        @record["last_seen_at"] = now
        persist!
        emit("mission:interrupt", id: @id, previous_scope: @record["scope"], next_scope: relative(scope))
      end

      def active_mission_conflict(record, goal:, scope:)
        "mission already active for #{record["scope"]} (requested #{relative(scope)}; #{record["goal"]} != #{goal})"
      end

      # An already-durable objective with the same goal and scope is reused as
      # :active (its handle is adopted) or :blocked (left untouched); anything
      # else starts a fresh record.
      def queued_reuse_state(current, goal:, scope:)
        return nil unless current && current["goal"].to_s == goal.to_s &&
                          current["scope"].to_s == relative(scope).to_s

        return :active if %w[running waiting].include?(current["state"].to_s)

        current["state"].to_s == "blocked" ? :blocked : nil
      end

      def queue_unlocked!
        @record["state"] = "waiting"
        @record["stage"] = "discover"
        @record["attempt_count"] = 0
        @record["next_wake_at"] = now
        @record["lease_owner"] = nil
        @record["lease_until"] = nil
      end

      # A record that is not reusable is superseded, interrupted, or refused
      # before a fresh record is started for the requested target.
      def restart_unlocked!(current, goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
        if manually_supersedable?(current, origin:)
          supersede_waiting_unlocked!(current, goal:, scope:)
        elsif same_process_mission?(current) && active_for_other_target?(current, goal:, scope:)
          interrupt_for_next_target_unlocked!(current, goal:, scope:)
        elsif active_for_other_target?(current, goal:, scope:)
          raise active_mission_conflict(current, goal:, scope:)
        end

        start_unlocked!(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
        persist!
      end

      def start_unlocked!(goal:, scope:, model:, effort:, plan:, origin: "unknown", auto_continue: false,
                          mode: "repair", risk: nil, intent: nil)
        @claimed = true
        @id = SecureRandom.hex(10)
        @record = fresh_record(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
      end

      def fresh_record(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
        fresh_record_identity(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
          .merge(fresh_record_state)
          .merge(fresh_record_lease)
      end

      def fresh_record_identity(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
        {
          "version" => VERSION,
          "id" => @id,
          "state" => "running",
          "stage" => "execute",
          "goal" => goal.to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
          "scope" => relative(scope),
          "model" => model.to_s,
          "effort" => normalize_effort(effort),
          "operator" => operator_fields(mode, risk, intent),
          "plan" => plan.to_s.byteslice(0, MAX_PLAN_BYTES),
          "summary" => nil,
          "origin" => origin.to_s,
          "auto_continue" => auto_continue == true,
          "started_at" => now,
          "finished_at" => nil,
        }
      end

      def fresh_record_state
        {
          "checkpoint" => nil,
          "artifacts" => [],
          "proof" => nil,
          "repository_pushes" => [],
          "repository_write_root" => nil,
          "repository_writes" => {},
          "error" => nil,
        }
      end

      def fresh_record_lease
        {
          "attempt_count" => 1,
          "retry_count" => 0,
          "next_wake_at" => nil,
          "wake_reason" => nil,
          "wake_requested" => false,
          "last_seen_at" => now,
          "lease_owner" => self.class.instance_id,
          "lease_until" => (Time.now.utc + LEASE_SECONDS).iso8601,
        }
      end

      def operator_fields(mode, risk, intent)
        {
          "mode" => Master::Operator::Mode.for(mode).to_s,
          "risk" => risk&.to_sym,
          "intent" => intent&.to_sym,
        }.compact
      end

      def normalize_effort(value)
        text = value.to_s.downcase
        %w[low medium high].include?(text) ? text : "medium"
      end
    end
  end
end
