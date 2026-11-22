# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # Lease custody, re-opening the class defined in fix/mission.rb: the
      # heartbeat that renews a claimed attempt's lease, hold_lease! as the
      # fence before any effect that leaves the process, and the claim plus
      # liveness/expiry predicates the run-state machine stands on.
      def heartbeat!
        with_lock do
          load_writable_unlocked!
          return self unless @record
          # A heartbeat is not a general "last seen" write. A fresh, unclaimed
          # handle may observe another worker's mission, but must not mutate its
          # timestamps or make a stale owner look alive.
          return self unless @record["state"] == "running" &&
                             @record["lease_owner"].to_s == self.class.instance_id

          @record["last_seen_at"] = now
          @record["lease_until"] = (Time.now.utc + LEASE_SECONDS).iso8601
          persist!
        end
        self
      end

      # Called before an effect that leaves the process: a commit or a push.
      # A claimed handle may act only while its mission is running under its
      # own lease; it renews that lease here, so a long run keeps it without a
      # supervisor, and another worker cannot claim it between this check and
      # the commit. A lease taken over, or a mission stopped, raises Fenced.
      def hold_lease!
        return self unless @claimed

        with_lock do
          current = load_record
          reason = fence_reason(current)
          reason ||= "mission #{@id} is #{current["state"]}, not running" unless current["state"] == "running"
          if reason
            emit("mission:fenced", id: @id, reason:)
            raise Fenced, reason
          end

          @record = current
          @record["lease_owner"] = self.class.instance_id
          @record["lease_until"] = (Time.now.utc + LEASE_SECONDS).iso8601
          @record["last_seen_at"] = now
          persist!
        end
        self
      end

      private

      def mission_live?(record)
        return false unless record["state"].to_s == "running"
        return false if lease_expired?(record)

        owner = record["lease_owner"].to_s
        return true if owner.empty?
        return true unless owner.start_with?("#{Socket.gethostname}:")

        pid = owner.split(":", 3)[1].to_i
        return true if record["lease_owner"].to_s == self.class.instance_id
        return false if pid <= 0

        process_alive?(pid)
      end

      def process_alive?(pid)
        Process.kill(0, pid.to_i)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def claim_unlocked!
        if @record["state"] == "running" &&
           @record["lease_owner"].to_s != self.class.instance_id &&
           !lease_expired?(@record) && mission_live?(@record)
          raise "mission already leased by pid=#{@record["lease_owner"]}"
        end

        @claimed = true
        @record["state"] = "running"
        @record["stage"] = "execute"
        @record["attempt_count"] = @record.fetch("attempt_count", 0).to_i + 1
        @record["attempt_started_at"] = now
        @record["last_seen_at"] = now
        @record["next_wake_at"] = nil
        @record["wake_reason"] = nil
        @record["lease_owner"] = self.class.instance_id
        @record["lease_until"] = (Time.now.utc + LEASE_SECONDS).iso8601
      end

      def lease_expired?(record)
        value = record["lease_until"]
        return true if value.to_s.empty?

        Time.iso8601(value.to_s) <= Time.now.utc
      rescue ArgumentError
        true
      end
    end
  end
end
