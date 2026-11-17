# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # The durable record's shape and its disk round trip, re-opening the
      # class defined in fix/mission.rb: the namespaced state paths, the
      # version migrations that normalize every read, and the writable load
      # and atomic persist legs every mutation stands on.
      class << self
        def record_path(root:, namespace: current_namespace)
          suffix = normalize_namespace(namespace)
          relative = suffix ? "mission-#{suffix}.json" : "mission.json"
          File.join(MasterPaths.fix_state(root: root), relative)
        end

        def current(root: Master::ROOT, namespace: current_namespace)
          path = record_path(root:, namespace:)
          candidates = [path]
          suffix = normalize_namespace(namespace)
          name = suffix ? "mission-#{suffix}.json" : "mission.json"
          workspace = File.basename(File.expand_path(root)) == "MASTER" ? File.dirname(File.expand_path(root)) : File.expand_path(root)
          candidates.concat([
            File.join(File.expand_path(root), ".master", name),
            File.join(workspace, ".master", name),
            File.join(workspace, "MASTER", ".master", name),
          ])
          source = candidates.uniq.find { |candidate| File.file?(candidate) && !File.symlink?(candidate) }
          return unless source

          record = JSON.parse(File.read(source, encoding: "UTF-8"))
          migrate_record(record, root:)
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "mission.current")
          nil
        end

        private

        def migrate_record(record, now: Time.now.utc.iso8601, root: nil)
          version = record["version"].to_i
          migrated = if version == VERSION
                       normalize_v2(record)
                     elsif version == 1
                       migrate_v1(record, now:)
                     else
                       raise "mission version #{record["version"]} is unsupported"
                     end
          root_scope(migrated, root)
        end

        def lock_file_path(root:, namespace: current_namespace)
          suffix = normalize_namespace(namespace)
          relative = suffix ? "mission-#{suffix}.lock" : "mission.lock"
          File.join(MasterPaths.fix_state(root: root), relative)
        end

        # Records written before #relative answered "." for the tree root hold its
        # absolute path; read them as "." so the same objective still matches.
        def root_scope(record, root)
          return record unless root

          scope = record["scope"].to_s
          return record unless scope.start_with?(File::SEPARATOR) && File.expand_path(scope) == File.expand_path(root)

          record.merge("scope" => ".")
        end

        def normalize_v2(record)
          out = record.dup
          out["operator"] = normalized_operator(record)
          out["repository_write_root"] = nil unless out["repository_write_root"].is_a?(String)
          out["proof"] = out["proof"].is_a?(Hash) ? out["proof"] : nil
          out["repository_pushes"] = normalized_pushes(out["repository_pushes"])
          out["repository_writes"] = normalized_writes(out["repository_writes"])
          out
        end

        def normalized_operator(record)
          operator = record["operator"].is_a?(Hash) ? record["operator"] : {}
          mode = operator["mode"].to_s
          mode = "repair" unless %w[observe plan repair deploy].include?(mode)

          { "mode" => mode, "risk" => operator["risk"], "intent" => operator["intent"] }.compact
        end

        def normalized_pushes(pushes)
          Array(pushes).filter_map do |row|
            next unless row.is_a?(Hash) && row["remote"] == "origin" && row["branch"] == "main"
            next unless row["commit"].to_s.match?(/\A[0-9a-f]{40}\z/i)

            { "remote" => "origin", "branch" => "main", "commit" => row["commit"].to_s,
              "pushed_at" => row["pushed_at"].to_s }
          end.uniq { |row| row["commit"] }.last(32)
        end

        def normalized_writes(writes)
          safe = writes.is_a?(Hash) ? writes : {}
          safe.each_with_object({}) do |(path, digest), clean|
            key = path.to_s
            clean[key] = digest.to_s if !key.empty? && !key.split("/").include?("..") &&
                                        digest.to_s.match?(/\A[0-9a-f]{64}\z/i)
          end
        end

        def migrate_v1(record, now:)
          state = record["state"].to_s
          unless %w[running completed failed interrupted].include?(state)
            raise "mission v1 state #{state.inspect} is unsupported"
          end

          migrate_v1_identity(record, state, now)
            .merge(migrate_v1_progress(record, now))
            .merge(migrate_v1_schedule(record, state, now))
        end

        def migrate_v1_identity(record, state, now)
          {
            "version" => VERSION,
            "id" => record["id"].to_s,
            "state" => state == "running" ? "waiting" : state,
            "stage" => STAGES.include?(record["stage"].to_s) ? record["stage"].to_s : "discover",
            "goal" => record["goal"].to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
            "scope" => record["scope"].to_s,
            "model" => record["model"].to_s,
            "effort" => %w[low medium high].include?(record["effort"].to_s.downcase) ? record["effort"].to_s.downcase : "medium",
            "operator" => { "mode" => "repair", "risk" => nil, "intent" => nil },
            "plan" => record["plan"].to_s.byteslice(0, MAX_PLAN_BYTES),
            "summary" => record["summary"],
            "origin" => record["origin"].to_s.empty? ? "legacy" : record["origin"].to_s,
            "auto_continue" => false,
            "started_at" => record["started_at"] || now,
            "finished_at" => record["finished_at"],
          }
        end

        def migrate_v1_progress(record, now)
          {
            "checkpoint" => record["checkpoint"],
            "artifacts" => Array(record["artifacts"]).map(&:to_s).uniq.last(32),
            "proof" => nil,
            "repository_pushes" => [],
            "repository_write_root" => nil,
            "repository_writes" => {},
            "error" => record["error"],
          }
        end

        def migrate_v1_schedule(record, state, now)
          {
            "attempt_count" => 1,
            "retry_count" => 0,
            "next_wake_at" => state == "running" ? now : nil,
            "wake_reason" => state == "running" ? "migrated from mission v1" : nil,
            "wake_requested" => false,
            "last_seen_at" => record["last_seen_at"] || record["started_at"] || now,
            "lease_owner" => nil,
            "lease_until" => nil,
          }
        end
      end

      private

      # Like load_current_unlocked!, but a handle that claimed a mission may write only that
      # mission, and only while no other worker holds its lease. Unclaimed handles (the
      # supervisor, an operator command) keep the plain read.
      def load_writable_unlocked!
        return load_current_unlocked! unless @claimed

        current = load_record
        reason = fence_reason(current)
        if reason
          emit("mission:fenced", id: @id, reason:)
          raise Fenced, reason
        end

        @record = current
      end

      def fence_reason(current)
        return "mission #{@id} no longer exists" unless current
        return "mission #{@id} was replaced by #{current["id"]}" unless current["id"] == @id

        owner = current["lease_owner"].to_s
        return if current["state"] != "running" || owner.empty? || owner == self.class.instance_id

        "mission #{@id} is leased to another worker"
      end

      def load_current_unlocked!
        @record = load_record
        @id = @record && @record["id"]
      end

      def load_record
        path = self.class.record_path(root: @root, namespace: @namespace)
        return unless File.file?(path)

        raw = JSON.parse(File.read(path, encoding: "UTF-8"))
        migrated = self.class.send(:migrate_record, raw, root: @root)
        persist_record(path, migrated) if migrated != raw
        migrated
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "mission.load")
        raise "mission state is corrupt: #{e.message}"
      end

      def persist!
        path = self.class.record_path(root: @root, namespace: @namespace)
        persist_record(path, @record)
      end

      def persist_record(path, record)
        # .master must stay owner-private (0700) or the Kernel execution lock
        # refuses the workspace; a default umask of 0002 would leave it 0775.
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
        write_atomic(path, JSON.pretty_generate(record) + "\n", mode: 0o600)
      end
    end
  end
end
