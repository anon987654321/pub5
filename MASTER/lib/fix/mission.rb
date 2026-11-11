# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"
require "securerandom"
require "socket"
require "time"
require_relative "../io/atomic_write"
require_relative "task_contract"

module Master
  module Fix
    # Mission is the durable objective. A FixLoop execution is only one attempt
    # to advance it; process death must never erase the work that remains.
    class Mission
      include ::Master::Io::AtomicWrite

      VERSION = 2
      REL_PATH = ".master/mission.json"
      LOCK_PATH = ".master/mission.lock"
      NAMESPACE_KEY = :master_fix_mission_namespace
      NAMESPACE_PATTERN = /\A[a-z][a-z0-9_-]{0,31}\z/.freeze
      MAX_GOAL_BYTES = 2_048
      MAX_PLAN_BYTES = 4_096
      LEASE_SECONDS = 300
      LEASE_RENEW_SECONDS = 60
      RETRY_BASE_SECONDS = 60
      RETRY_MAX_SECONDS = 3_600
      STATES = %w[queued running waiting completed failed blocked interrupted cancelled unknown_outcome recovery_failed].freeze
      RESUMABLE_STATES = %w[running waiting].freeze
      STAGES = %w[discover plan execute verify deliver].freeze

      attr_reader :root, :id

      # A worker that claimed a mission and then lost it. Its lease expired and another worker
      # claimed the mission, or a newer mission replaced it: a write now would land on work
      # someone else owns, so it is refused rather than made.
      class Fenced < StandardError; end

      def self.instance_id
        if @instance_pid != Process.pid
          @instance_pid = Process.pid
          @instance_id = "#{Socket.gethostname}:#{Process.pid}:#{SecureRandom.hex(8)}"
        end
        @instance_id
      end

      def self.current_namespace
        Thread.current.thread_variable_get(NAMESPACE_KEY)
      end

      # Scope a synchronous repair invocation to its own durable mission file.
      # Thread variables are deliberate: ordinary thread-local state is fiber-local
      # on modern Ruby and can leak a namespace across a scheduler boundary.
      def self.with_namespace(namespace)
        thread = Thread.current
        previous = thread.thread_variable_get(NAMESPACE_KEY)
        thread.thread_variable_set(NAMESPACE_KEY, normalize_namespace(namespace))
        yield
      ensure
        thread&.thread_variable_set(NAMESPACE_KEY, previous)
      end

      def self.normalize_namespace(value)
        return if value.nil?

        normalized = value.to_s
        raise ArgumentError, "invalid mission namespace" unless normalized.match?(NAMESPACE_PATTERN)

        normalized.freeze
      end

      def self.record_path(root:, namespace: current_namespace)
        suffix = normalize_namespace(namespace)
        relative = suffix ? ".master/mission-#{suffix}.json" : REL_PATH
        File.join(File.expand_path(root), relative)
      end

      def self.lock_file_path(root:, namespace: current_namespace)
        suffix = normalize_namespace(namespace)
        relative = suffix ? ".master/mission-#{suffix}.lock" : LOCK_PATH
        File.join(File.expand_path(root), relative)
      end

      def initialize(root: Master::ROOT, bus: nil, checkpoint: nil, namespace: self.class.current_namespace)
        @root = File.expand_path(root)
        @namespace = self.class.normalize_namespace(namespace)
        @bus = bus
        @checkpoint = checkpoint
        @id = nil
        @record = nil
      end

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
          if current && current["goal"].to_s == goal.to_s && current["scope"].to_s == relative(scope).to_s &&
             %w[running waiting].include?(current["state"].to_s)
            @record = current
            @id = current["id"]
            return self
          end

          return self if current && current["goal"].to_s == goal.to_s && current["scope"].to_s == relative(scope).to_s &&
                          current["state"].to_s == "blocked"

          raise active_mission_conflict(current, goal:, scope:) if active_for_other_target?(current, goal:, scope:)

          start_unlocked!(goal:, scope:, model:, effort:, plan:, origin:, auto_continue:, mode:, risk:, intent:)
          @record["state"] = "waiting"
          @record["stage"] = "discover"
          @record["attempt_count"] = 0
          @record["next_wake_at"] = now
          @record["lease_owner"] = nil
          @record["lease_until"] = nil
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
            if manually_supersedable?(current, origin:)
              supersede_waiting_unlocked!(current, goal:, scope:)
            elsif same_process_mission?(current) && active_for_other_target?(current, goal:, scope:)
              interrupt_for_next_target_unlocked!(current, goal:, scope:)
            elsif active_for_other_target?(current, goal:, scope:)
              raise active_mission_conflict(current, goal:, scope:)
            end

            start_unlocked!(
              goal:, scope:, model:, effort:, plan:, origin:, auto_continue:,
              mode:, risk:, intent:
            )
            persist!
            resumed = false
          end
        end
        emit(resumed ? "mission:resume" : "mission:start", id: @id, goal: @record["goal"],
             scope: @record["scope"], attempt: @record["attempt_count"])
        self
      end

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
        # reason is read by the emit after with_lock returns; a block-local would not survive.
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

      # Durable content receipts let the next bounded attempt continue the
      # same authorised task without treating a fresh process as a new grant.
      # Every read re-hashes the live file; absent, replaced or symlinked paths
      # lose their receipt rather than inherit stale authority.
      def repository_writes(repository_root:)
        repo = File.realpath(repository_root)
        record = @record || self.class.current(root: @root)
        return {} unless record && record["repository_write_root"] == repo

        (record["repository_writes"] || {}).each_with_object({}) do |(path, digest), found|
          full = repository_full_path(path, repo)
          next unless full && Digest::SHA256.file(full).hexdigest == digest

          found[path] = digest
        end
      rescue SystemCallError, ArgumentError
        {}
      end

      def record_repository_write!(path:, content:, repository_root:)
        repo = File.realpath(repository_root)
        relative = repository_relative_path(path, repo)
        return false unless relative

        digest = Digest::SHA256.hexdigest(content.to_s)
        full = File.join(repo, relative)
        return false unless Digest::SHA256.file(full).hexdigest == digest

        with_lock do
          load_writable_unlocked!
          return false unless @record

          if @record["repository_write_root"] != repo
            @record["repository_write_root"] = repo
            @record["repository_writes"] = {}
          end
          @record["repository_writes"] ||= {}
          @record["repository_writes"][relative] = digest
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:write_receipt", id: @id, path: relative, digest:)
        true
      rescue SystemCallError, ArgumentError => error
        emit("mission:write_receipt_refused", id: @id, reason: error.class.name)
        false
      end

      def record_proof!(proof:)
        source = proof.is_a?(Hash) ? proof : {}
        value = lambda do |key|
          source.key?(key) ? source[key] : source[key.to_s]
        end
        paths = lambda do |key|
          Array(value.call(key)).map(&:to_s).uniq.select do |path|
            !path.empty? && !Pathname.new(path).absolute? && !path.split("/").include?("..")
          end.first(128)
        end
        receipt = {
          "proved" => value.call(:proved) == true,
          "answerable" => value.call(:answerable) == true,
          "evidence_score" => Integer(value.call(:evidence) || 0),
          "repository_delivery" => value.call(:repository_delivery) == true,
          "write_paths" => paths.call(:write_paths),
          "delivery_paths" => paths.call(:delivery_paths),
          "council_cleared" => value.call(:cleared) == true,
          "ideation_satisfied" => value.call(:writable) == true,
          "generation" => Integer(value.call(:generation) || 0),
          "write_lines" => Integer(value.call(:write_lines) || 0),
        }
        return false unless receipt["proved"] || receipt["answerable"]

        with_lock do
          load_writable_unlocked!
          return false unless @record

          @record["proof"] = receipt
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:proof", id: @id, proved: receipt["proved"], answerable: receipt["answerable"],
                             evidence_score: receipt["evidence_score"], write_paths: receipt["write_paths"].size)
        true
      rescue ArgumentError, TypeError
        false
      end

      def record_fix_proof!(status:, scope_paths:, report:, command_proof:)
        text = report.to_s
        return false unless status.to_s == "pass"
        return false unless text.match?(/\bfix done\b/i)
        return false unless text.match?(/\bproof:\s*(?!no proof ran)/i)
        return false unless text.match?(/hard red 0\b/i)
        return false if text.match?(/unmeasured [1-9]\d*\b/i)
        return false if text.match?(/review\d+:\s*(?:incomplete|complete with open findings)\b/i)

        paths = Array(scope_paths).map(&:to_s).uniq
        return false if paths.empty? || paths.size > 128
        return false unless paths.all? do |path|
          !path.empty? && !Pathname.new(path).absolute? && !path.split("/").include?("..")
        end

        line = text.lines.find { |entry| entry.match?(/fix done/i) && entry.match?(/proof:/i) }.to_s.strip
        with_lock do
          load_writable_unlocked!
          return false unless @record && @record["origin"].to_s == "backlog"

          plan = JSON.parse(@record["plan"].to_s)
          required = Array(plan["proof_types"]).map(&:to_s)
          allowed = TaskContract.template.fetch("proof_types").map(&:to_s)
          map_version = Backlog::ProofMap::VERSION if defined?(Backlog::ProofMap::VERSION)
          return false unless plan["executor"] == "root_todo" && plan["proof_map_version"] == map_version
          return false if required.empty? || required.uniq != required || (required - allowed).any?

          evidence = command_proof.to_h.transform_keys(&:to_s)
          proof_type = evidence.fetch("proof_type").to_s
          return false unless required.include?(proof_type)
          return false unless evidence["status"].to_s == "pass"
          return false unless evidence["exit_status"].is_a?(Integer) && evidence["exit_status"].zero?
          return false unless evidence["command_digest"].to_s == Digest::SHA256.hexdigest(plan.fetch("done_when").to_s)
          return false unless evidence["output_digest"].to_s.match?(/\A[0-9a-f]{64}\z/)
          return false unless evidence["output_bytes"].is_a?(Integer) && evidence["output_bytes"] >= 0
          return false unless evidence["duration_ms"].is_a?(Integer) && evidence["duration_ms"] >= 0
          cwd = evidence["cwd"].to_s
          return false if cwd.empty? || Pathname.new(cwd).absolute? || cwd.split("/").include?("..")

          command_evidence = {
            "proof_type" => proof_type,
            "status" => "pass",
            "exit_status" => 0,
            "command_digest" => evidence.fetch("command_digest"),
            "output_digest" => evidence.fetch("output_digest"),
            "output_bytes" => evidence.fetch("output_bytes").to_i,
            "cwd" => cwd,
            "duration_ms" => evidence.fetch("duration_ms").to_i,
          }
          @record["proof"] = {
            "kind" => "fix_pipeline",
            "status" => "pass",
            "scope_paths" => paths,
            "report_digest" => Digest::SHA256.hexdigest(text),
            "proof_summary" => line.byteslice(0, 512),
            "proof_map_version" => plan.fetch("proof_map_version"),
            "required_proof_types" => required,
            "command_evidence" => command_evidence,
          }
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:proof", id: @id, source: "fix_pipeline", status: "pass", scope_paths: paths.size)
        true
      rescue ArgumentError, TypeError, JSON::ParserError, KeyError, NoMethodError
        false
      end

      def record_repository_push!(remote:, branch:, commit:)
        return false unless remote.to_s == "origin" && branch.to_s == "main"
        return false unless commit.to_s.match?(/\A[0-9a-f]{40}\z/i)

        with_lock do
          load_writable_unlocked!
          return false unless @record && @record["origin"].to_s == "backlog"

          pushes = @record["repository_pushes"] ||= []
          pushes << { "remote" => "origin", "branch" => "main", "commit" => commit.to_s,
                      "pushed_at" => now }
          @record["repository_pushes"] = pushes.uniq { |row| row["commit"] }.last(32)
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:repository_push", id: @id, remote: "origin", branch: "main", commit:)
        true
      rescue ArgumentError, TypeError
        false
      end

      def record_repository_commit!(expected_hashes:, repository_root:)
        repo = File.realpath(repository_root)
        receipts = expected_hashes.is_a?(Hash) ? expected_hashes : {}
        with_lock do
          load_writable_unlocked!
          return false unless @record && @record["repository_write_root"] == repo

          writes = @record["repository_writes"] ||= {}
          receipts.each do |path, digest|
            relative = repository_relative_path(path, repo)
            next unless relative && writes[relative] == digest.to_s

            full = File.join(repo, relative)
            writes.delete(relative) if Digest::SHA256.file(full).hexdigest == digest.to_s
          end
          @record["last_seen_at"] = now
          persist!
        end
        true
      rescue SystemCallError, ArgumentError => error
        emit("mission:commit_receipt_refused", id: @id, reason: error.class.name)
        false
      end

      def record
        @record&.dup
      end

      def self.current(root: Master::ROOT, namespace: current_namespace)
        path = record_path(root:, namespace:)
        return unless File.file?(path)

        record = JSON.parse(File.read(path, encoding: "UTF-8"))
        migrate_record(record, root:)
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "mission.current")
        nil
      end

      def self.migrate_record(record, now: Time.now.utc.iso8601, root: nil)
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

      # Records written before #relative answered "." for the tree root hold its
      # absolute path; read them as "." so the same objective still matches.
      def self.root_scope(record, root)
        return record unless root

        scope = record["scope"].to_s
        return record unless scope.start_with?(File::SEPARATOR) && File.expand_path(scope) == File.expand_path(root)

        record.merge("scope" => ".")
      end

      def self.normalize_v2(record)
        out = record.dup
        operator = record["operator"].is_a?(Hash) ? record["operator"] : {}
        mode = operator["mode"].to_s
        mode = "repair" unless %w[observe plan repair deploy].include?(mode)
        out["operator"] = {
          "mode" => mode,
          "risk" => operator["risk"],
          "intent" => operator["intent"],
        }.compact
        out["repository_write_root"] = nil unless out["repository_write_root"].is_a?(String)
        out["proof"] = out["proof"].is_a?(Hash) ? out["proof"] : nil
        pushes = Array(out["repository_pushes"])
        out["repository_pushes"] = pushes.filter_map do |row|
          next unless row.is_a?(Hash) && row["remote"] == "origin" && row["branch"] == "main"
          next unless row["commit"].to_s.match?(/\A[0-9a-f]{40}\z/i)

          { "remote" => "origin", "branch" => "main", "commit" => row["commit"].to_s,
            "pushed_at" => row["pushed_at"].to_s }
        end.uniq { |row| row["commit"] }.last(32)
        writes = out["repository_writes"].is_a?(Hash) ? out["repository_writes"] : {}
        out["repository_writes"] = writes.each_with_object({}) do |(path, digest), clean|
          key = path.to_s
          clean[key] = digest.to_s if !key.empty? && !key.split("/").include?("..") &&
                                      digest.to_s.match?(/\A[0-9a-f]{64}\z/i)
        end
        out
      end

      def self.migrate_v1(record, now:)
        state = record["state"].to_s
        unless %w[running completed failed interrupted].include?(state)
          raise "mission v1 state #{state.inspect} is unsupported"
        end

        {
          "version" => VERSION,
          "id" => record["id"].to_s,
          "state" => state == "running" ? "waiting" : state,
          "stage" => STAGES.include?(record["stage"].to_s) ? record["stage"].to_s : "discover",
          "goal" => record["goal"].to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
          "scope" => record["scope"].to_s,
          "model" => record["model"].to_s,
          "effort" => %w[low medium high].include?(record["effort"].to_s.downcase) ? record["effort"].to_s.downcase : "medium",
          "operator" => {
            "mode" => "repair",
            "risk" => nil,
            "intent" => nil,
          },
          "plan" => record["plan"].to_s.byteslice(0, MAX_PLAN_BYTES),
          "summary" => record["summary"],
          "origin" => record["origin"].to_s.empty? ? "legacy" : record["origin"].to_s,
          "auto_continue" => false,
          "started_at" => record["started_at"] || now,
          "finished_at" => record["finished_at"],
          "checkpoint" => record["checkpoint"],
          "artifacts" => Array(record["artifacts"]).map(&:to_s).uniq.last(32),
          "proof" => nil,
          "repository_pushes" => [],
          "repository_write_root" => nil,
          "repository_writes" => {},
          "error" => record["error"],
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

      def self.block_current(root: Master::ROOT, reason:)
        mission = new(root:)
        mission.send(:load_current_unlocked!)
        mission.block!(reason:)
        mission
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Mission.block_current")
        mission
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

      def active_mission_conflict(record, goal:, scope:)
        "mission already active for #{record["scope"]} (requested #{relative(scope)}; #{record["goal"]} != #{goal})"
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

      def start_unlocked!(goal:, scope:, model:, effort:, plan:, origin: "unknown", auto_continue: false,
                          mode: "repair", risk: nil, intent: nil)
        @claimed = true
        @id = SecureRandom.hex(10)
        @record = {
          "version" => VERSION,
          "id" => @id,
          "state" => "running",
          "stage" => "execute",
          "goal" => goal.to_s.byteslice(0, MAX_GOAL_BYTES).to_s,
          "scope" => relative(scope),
          "model" => model.to_s,
          "effort" => normalize_effort(effort),
          "operator" => {
            "mode" => Master::Operator::Mode.for(mode).to_s,
            "risk" => risk&.to_sym,
            "intent" => intent&.to_sym,
          }.compact,
          "plan" => plan.to_s.byteslice(0, MAX_PLAN_BYTES),
          "summary" => nil,
          "origin" => origin.to_s,
          "auto_continue" => auto_continue == true,
          "started_at" => now,
          "finished_at" => nil,
          "checkpoint" => nil,
          "artifacts" => [],
          "proof" => nil,
          "repository_pushes" => [],
          "repository_write_root" => nil,
          "repository_writes" => {},
          "error" => nil,
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
        migrated = self.class.migrate_record(raw, root: @root)
        persist_record(path, migrated) if migrated != raw
        migrated
      rescue JSON::ParserError => e
        Master::Ground::Swallow.log(e, context: "mission.load")
        raise "mission state is corrupt: #{e.message}"
      end

      def backoff_seconds(retries)
        [RETRY_BASE_SECONDS * (2**[retries - 1, 5].min), RETRY_MAX_SECONDS].min
      end

      def normalize_effort(value)
        text = value.to_s.downcase
        %w[low medium high].include?(text) ? text : "medium"
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

      def with_lock
        lock_path = self.class.lock_file_path(root: @root, namespace: @namespace)
        FileUtils.mkdir_p(File.dirname(lock_path), mode: 0o700)
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |io|
          io.flock(File::LOCK_EX)
          yield
        ensure
          io&.flock(File::LOCK_UN)
        end
      end

      def emit(event, payload = {}, **fields)
        @bus&.publish(event, payload.merge(fields))
      rescue StandardError => e
        warn("mission0: #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
      end

      def repository_relative_path(path, repository_root)
        value = path.to_s
        return if value.empty? || value.include?("\0") || value.split(%r{[\\/]}).include?("..")

        full = File.expand_path(value, repository_root)
        return unless full.start_with?(repository_root + File::SEPARATOR)
        return if full.split(File::SEPARATOR).include?(".git")
        return unless File.file?(full) && !File.symlink?(full)

        real = File.realpath(full)
        return unless real.start_with?(repository_root + File::SEPARATOR)

        real.delete_prefix(repository_root + File::SEPARATOR).tr(File::SEPARATOR, "/")
      rescue ArgumentError, SystemCallError
        nil
      end

      def repository_full_path(path, repository_root)
        relative = repository_relative_path(path, repository_root)
        relative && File.join(repository_root, relative)
      end

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        root = File.expand_path(@root)
        # The tree root itself is "."; delete_prefix below would leave it absolute.
        return "." if full == root
        return path.to_s unless full.start_with?(root + File::SEPARATOR)

        full.delete_prefix(root + File::SEPARATOR)
      rescue ArgumentError
        path.to_s
      end

      def now = Time.now.utc.iso8601
    end
  end
end
