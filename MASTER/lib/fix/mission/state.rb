# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # The attempt's progress surface, re-opening the class defined in
      # fix/mission.rb: stage transitions, wake and requeue intake, deferral,
      # blocking (including the snapshot-guarded variant the task steward
      # uses), terminal finishes and failures, and the artifact register.
      # Every mutation loads the record under the mission lock before writing.
      def transition!(stage, **payload)
        with_lock do
          load_writable_unlocked!
          return self unless @record
          stage = stage.to_s
          raise ArgumentError, "unknown mission stage: #{stage}" unless STAGES.include?(stage)

          @record["stage"] = stage
          payload.each { |key, value| assign_payload(key, value) }
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:stage", id: @id, stage:, **payload)
        self
      end

      def checkpoint!(files: [])
        return self unless @checkpoint

        checkpoint = @checkpoint.call(id: @id, root: @root, files: Array(files)).transform_keys(&:to_s)
        with_lock do
          load_writable_unlocked!
          @record["checkpoint"] = checkpoint
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:checkpoint", id: @id, checkpoint: checkpoint["id"], files: checkpoint["files"].size)
        self
      end

      # Wake the current mission immediately. Used by file watchers and other
      # event sources; they request work, the supervisor decides when to execute.
      def wake!(reason: "external_event")
        with_lock do
          load_current_unlocked!
          return self unless @record
          return self unless RESUMABLE_STATES.include?(@record["state"].to_s)

          reason = reason.to_s[0, 240]
          if @record["state"].to_s == "running"
            @record["wake_requested"] = true
            @record["wake_reason"] = reason
          else
            @record["state"] = "waiting"
            @record["next_wake_at"] = now
            @record["wake_reason"] = reason
            @record["lease_owner"] = nil
            @record["lease_until"] = nil
          end
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:wake", id: @id, reason:)
        self
      end

      # Turn a wake received during an attempt into durable work for
      # the next attempt without treating an external event as a retry failure.
      def requeue_if_requested!
        # reason is read by the emit after with_lock returns; a block local would not survive.
        reason = nil
        with_lock do
          load_current_unlocked!
          return false unless @record && @record["wake_requested"]

          reason = @record["wake_reason"].to_s
          @record["state"] = "waiting"
          @record["stage"] = "verify"
          @record["next_wake_at"] = now
          @record["wake_requested"] = false
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:requeued", id: @id, reason:)
        true
      end

      def due?
        return false unless @record

        due_at = @record["next_wake_at"]
        return true if due_at.to_s.empty?

        Time.iso8601(due_at.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end

      def defer!(reason:, seconds: nil)
        # delay/retries are read after with_lock returns; block locals die with it.
        delay = 0
        retries = 0
        with_lock do
          load_current_unlocked!
          return self unless @record

          retries = @record.fetch("retry_count", 0).to_i + 1
          delay = seconds || backoff_seconds(retries)
          @record["state"] = "waiting"
          @record["stage"] = "verify"
          @record["retry_count"] = retries
          @record["next_wake_at"] = (Time.now.utc + delay).iso8601
          @record["wake_reason"] = reason.to_s[0, 240]
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:deferred", id: @id, reason:, delay_seconds: delay, retry_count: retries)
        self
      end

      def block!(reason:)
        with_lock do
          load_current_unlocked!
          return self unless @record

          @record["state"] = "blocked"
          @record["wake_reason"] = reason.to_s[0, 240]
          @record["next_wake_at"] = nil
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:block", id: @id, reason:)
        self
      end

      # Block only the same still-unleased objective observed by the caller.
      # The snapshot can race with a manual runner claiming or replacing the mission.
      def block_if_unleased!(id:, reason:)
        blocked = false
        with_lock do
          load_current_unlocked!
          return false unless @record && @record["id"] == id.to_s
          return false unless RESUMABLE_STATES.include?(@record["state"].to_s)
          return false if @record["state"].to_s == "running" && !lease_expired?(@record)

          @record["state"] = "blocked"
          @record["wake_reason"] = reason.to_s[0, 240]
          @record["next_wake_at"] = nil
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
          blocked = true
        end
        emit("mission:block", id: @id, reason:) if blocked
        blocked
      end

      def finish!(state: "completed", summary: nil)
        state = state.to_s
        raise ArgumentError, "unknown mission state: #{state}" unless STATES.include?(state)

        with_lock do
          load_writable_unlocked!
          return self unless @record

          @record["state"] = state
          @record["stage"] = "deliver" if state == "completed"
          @record["summary"] = summary.to_s.byteslice(0, 2_048) if summary
          @record["next_wake_at"] = nil
          # A finished attempt is terminal; nothing may continue it on its own.
          @record["auto_continue"] = false
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["finished_at"] = now
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:finish", id: @id, state:, summary: @record["summary"])
        self
      end

      def fail!(error)
        with_lock do
          load_writable_unlocked!
          return self unless @record

          @record["state"] = "failed"
          @record["error"] = error.to_s.byteslice(0, 1_200)
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:finish", id: @id, state: "failed", error: @record["error"])
        self
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}")
        self
      end

      private

      # No external caller (grep lib/ and test/ confirmed); retained as the
      # record's artifact register mutation, the non-payload sibling of
      # assign_payload's :artifact branch.
      def artifact!(path)
        return self if path.to_s.empty?

        with_lock do
          load_writable_unlocked!
          return self unless @record

          @record["artifacts"] = (@record.fetch("artifacts", []) + [relative(path)]).uniq.last(32)
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:artifact", id: @id, path: relative(path))
        self
      end

      def backoff_seconds(retries)
        [RETRY_BASE_SECONDS * (2**[retries - 1, 5].min), RETRY_MAX_SECONDS].min
      end

      def assign_payload(key, value)
        case key.to_sym
        when :plan then @record["plan"] = value.to_s.byteslice(0, MAX_PLAN_BYTES)
        when :artifact
          path = relative(value)
          @record["artifacts"] = (@record.fetch("artifacts", []) + [path]).uniq.last(32) if path
        when :checkpoint then @record["checkpoint"] = value
        when :summary then @record["summary"] = value.to_s.byteslice(0, MAX_PLAN_BYTES)
        end
      end
    end
  end
end
