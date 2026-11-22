# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "set"
require "securerandom"
require "socket"
require "time"
require_relative "../../io/atomic_write"
require_relative "../../boot/paths"
require_relative "../../trace/mutation_observer"
require_relative "../outcome_policy"
# The re-opened parts of this class, one responsibility each; every path is
# listed in data/autoload.yml under autoload.reopens_a_constant_defined_elsewhere.
require_relative "lifecycle_journal/runs"
require_relative "lifecycle_journal/reports"
require_relative "lifecycle_journal/architecture_reports"
require_relative "lifecycle_journal/report_matrix"
require_relative "lifecycle_journal/surface_evidence"
require_relative "lifecycle_journal/artifacts"
require_relative "lifecycle_journal/state_store"
require_relative "lifecycle_journal/legacy_state"

module Master
  module Fix
    class Kernel
      # Durable lifecycle journal for /fix runs.
      #
      # The journal is deliberately metadata-only. It never tries to reconstruct
      # files from JSON; Git, Checkpoint and the write journal remain the sources
      # of truth for content. Its job is to make interruption visible and let the
      # next run resume from a known completed pass instead of pretending the
      # previous run finished. This file holds the core run lifecycle and the
      # shared surface; the lifecycle_journal/ parts carry plan and pass
      # mutations, report persistence and verification, artifact safety, state
      # persistence and legacy migration.
      class LifecycleJournal
        include ::Master::Io::AtomicWrite

        VERSION = 1
        PATH = "fix_runs.json"
        LOCK = "fix_runs.lock"
        PENDING_MARKER = ".fix_runs.pending"
        MIGRATION_MARKER = ".legacy-migration.json"
        MAX_RUNS = 24
        ASSESSMENT_DIR = "fix_assessments"
        ARCHITECTURE_DIR = "fix_architecture"
        RESUMABLE_STATES = %w[active crashed delivery_failed].freeze

        class ArtifactReadError < StandardError
          attr_reader :status, :details

          def initialize(status, message, details = {})
            @status = status
            @details = details
            super(message)
          end
        end

        def self.instance_id
          return @instance_id if @instance_pid == Process.pid

          @instance_pid = Process.pid
          @instance_id = "#{Process.pid}:#{SecureRandom.hex(8)}"
        end

        def initialize(root:, bus: nil, state_root: nil)
          @root = File.expand_path(root)
          workspace = File.basename(@root) == "MASTER" ? File.dirname(@root) : @root
          @legacy_state_roots = [File.join(@root, ".master"), File.join(workspace, ".master"),
                                 File.join(workspace, "MASTER", ".master")].uniq
          @state_root = File.expand_path(state_root || MasterPaths.fix_state(root: @root))
          @local_state_root = @legacy_state_roots.include?(@state_root)
          @bus = bus
          @lifecycle_observer = Master::Trace::MutationObserver.new(
            root: @root, namespace: "fix:journal_lifecycle",
            subject_type: "run_journal", subject_id: "runs", bus: @bus
          )
          @pending_marker_owned = false
        end

        def start_or_resume(target:, files:, max_passes:, budget_seconds:)
          with_lock do
            data = load
            resumable = data["runs"].reverse.find { |run| RESUMABLE_STATES.include?(run["state"].to_s) }
            resumable = nil if resumable && (release_elsewhere(resumable, target) || release_spent(resumable) ||
                                             release_orphan(resumable))
            next resume_existing_run(resumable, target, data) if resumable

            create_new_run(target:, files:, max_passes:, budget_seconds:, data:)
          end
        rescue StandardError => e
          emit("fix:journal_error", operation: "start", error: e.message)
          raise
        end

        def active_pass(run)
          Array(run["passes"]).reverse.find { |row| %w[active delivery_failed].include?(row["state"].to_s) }
        end

        def next_pass(run)
          completed = Array(run["passes"]).reject { |row| row["state"].to_s == "active" }
          completed.map { |row| row["pass"].to_i }.max.to_i + 1
        end

        def remaining_seconds(run_id)
          run = load["runs"].find { |row| row["id"] == run_id }
          return 0.0 unless run

          remaining_for(run)
        rescue ArgumentError
          0.0
        end

        def history(limit: MAX_RUNS)
          load["runs"].last(limit)
        end

        # Called by Kernel before /fix status or execution first reads the
        # journal. Migration is serialized with all journal writers and has a
        # stable receipt, so later reads are cheap.
        def prepare_state!
          with_lock { load }
          true
        end

        private

        # A resumable run on another target whose process is gone would block
        # every other target until someone reran exactly that one: a MASTER/tools run
        # that crashed on dilla.rb's length refused /fix RAILS for good. It is
        # closed as interrupted, with the reason, and a live one still refuses.
        # True when the run was released.
        def release_elsewhere(run, target)
          return false if run["target"] == relative(target)
          same_process = run["process_token"].to_s == self.class.instance_id
          return false if !same_process && process_alive?(run["pid"])

          previous = run["state"]
          run["state"] = "interrupted"
          run["message"] = same_process ? "left #{previous}; #{relative(target)} followed in the same process" : "left #{previous}; #{relative(target)} started while its process was gone"
          run["finished_at"] = Time.now.utc.iso8601
          emit("fix:interrupted", run_id: run["id"], target: run["target"], previous_state: previous)
          true
        end

        # A run whose budget ran out while no process held it is over, not resumable. A MASTER run
        # that stopped on 2026-10-21 with thirty minutes of budget was resumed the next morning
        # with none left, and every /fix after it ended "budget exhausted before resume" without
        # trying a file. A live run keeps its own deadline, and one stopped mid-pass is resumed so its
        # transaction is recovered. True when the run was released.
        def release_spent(run)
          return false if process_alive?(run["pid"]) || active_pass(run) || remaining_for(run).positive?

          previous = run["state"]
          run["state"] = "interrupted"
          run["message"] = "left #{previous} with its budget spent; a new run started"
          run["finished_at"] = Time.now.utc.iso8601
          emit("fix:interrupted", run_id: run["id"], target: run["target"], previous_state: previous)
          true
        end

        # A run whose process is gone, when the operator started a fresh one (bin/fix-here sets
        # MASTER_FIX_FRESH=1 unless --resume). A run stopped by hand was resumed with its leftover
        # budget, 201 seconds once, and every restart began by closing it in the journal by hand.
        # Its open transaction is recovered before the journal is read (recover_stranded_transactions!).
        def release_orphan(run)
          return false unless ENV["MASTER_FIX_FRESH"] == "1"
          return false if process_alive?(run["pid"])

          previous = run["state"]
          run["state"] = "interrupted"
          run["message"] = "left #{previous} when its process ended; a fresh run started"
          run["finished_at"] = Time.now.utc.iso8601
          emit("fix:interrupted", run_id: run["id"], target: run["target"], previous_state: previous)
          true
        end

        def resume_existing_run(active, target, data)
          unless active["target"] == relative(target)
            raise "another fix run is active: #{active["id"]} for #{active["target"]}"
          end
          if active["state"] == "active" && active["pid"].to_i != Process.pid && process_alive?(active["pid"])
            raise "another fix process is active: #{active["id"]} pid=#{active["pid"]}"
          end
          previous_state = active["state"]
          active["state"] = "active"
          active["resumed_from"] = previous_state unless previous_state == "active"
          active["resumed_at"] = Time.now.utc.iso8601
          active["resume_count"] = active.fetch("resume_count", 0).to_i + 1
          remaining = remaining_for(active)
          persist(data)
          emit("fix:resume", run_id: active["id"], pass: next_pass(active),
                        resume_count: active["resume_count"], remaining_seconds: remaining)
          active.merge("resumed" => true, "remaining_seconds" => remaining)
        end

        def create_new_run(target:, files:, max_passes:, budget_seconds:, data:)
          now = Time.now.utc
          run = new_run_record(target, files, max_passes, budget_seconds, now)
          append_new_run(data, run)
          persist(data)
          emit("fix:start", run_id: run["id"], target: run["target"])
          run.merge("resumed" => false, "remaining_seconds" => Integer(budget_seconds).to_f)
        end

        def new_run_record(target, files, max_passes, budget_seconds, now)
          {
            "id" => SecureRandom.hex(10),
            "state" => "active",
            "target" => relative(target),
            "files" => Array(files).filter_map { |path| relative(path) }.uniq.sort,
            "max_passes" => Integer(max_passes),
            "budget_seconds" => Integer(budget_seconds),
            "started_at" => now.iso8601,
            "deadline_at" => (now + Integer(budget_seconds)).iso8601,
            "last_seen_at" => now.iso8601,
            "pid" => Process.pid,
            "process_token" => self.class.instance_id,
            "passes" => [],
          }
        end

        def append_new_run(data, run)
          data["runs"] << run
          data["runs"] = data["runs"].last(MAX_RUNS)
        end

        def active
          load["runs"].reverse.find { |run| run["state"] == "active" }
        end

        # No external caller (checked: only start_or_resume calls this, without
        # an explicit receiver, which private allows).
        def remaining_for(run)
          deadline = Time.iso8601(run["deadline_at"].to_s)
          now = Time.now.utc
          last = run["last_seen_at"] && Time.iso8601(run["last_seen_at"].to_s)
          return 0.0 if last && now < last

          remaining = [deadline - now, 0.0].max
          run["last_seen_at"] = now.iso8601
          remaining
        rescue ArgumentError
          0.0
        end

        def emit(event, **payload)
          @bus&.publish(event, **payload)
        rescue StandardError => e
          Master::Trace::Dmesg.once("fix0", "journal publish failed, #{e.class}: #{e.message}") if ENV["MASTER_TRACE_STRICT"] == "1"
          nil
        end

        def process_alive?(pid)
          value = pid.to_i
          return false if value <= 0

          Process.kill(0, value)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end

        def relative(path)
          value = path.to_s
          return if value.empty?

          full = File.expand_path(value, @root)
          root = File.expand_path(@root)
          return value unless full == root || full.start_with?(root + File::SEPARATOR)

          full.delete_prefix(root + File::SEPARATOR)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
