# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "kernel/lifecycle_journal"
require_relative "../boot/paths"
require_relative "kernel/execution_lock"
require_relative "kernel/lifecycle"
require_relative "task_contract"
require_relative "terminal_receipt"
# The hash-chained ledger (append path, verified read path, verify reader)
# re-opens this class; registered in data/autoload.yml under
# reopens_a_constant_defined_elsewhere.
require_relative "kernel/ledger"

module Master
  module Fix
    # Owns the hash-chained /fix coordinator lifecycle and keeps the replay
    # reader public for `bin/master replay <seq>`. It does not apply repairs;
    # FixLoop, RepairAdapter and Transaction retain the mutation responsibilities.
    # A broken chain is refused rather than returned as partial history.
    # The ledger itself (append, verified read, verify reader) re-opens this
    # class from kernel/ledger.rb.
    class Kernel
      include Lifecycle

      # Class-level compatibility settings remain visible to adapters. Serialize
      # every Kernel-backed fix run for the whole settings lifetime.
      SETTINGS_LOCK = Mutex.new

      def self.with_settings_lock
        owner = Thread.current.thread_variable_get(:master_fix_settings_owner)
        if owner
          raise ThreadError, "fix settings are owned by another fiber" unless owner.equal?(Fiber.current)

          return yield
        end

        SETTINGS_LOCK.synchronize do
          Thread.current.thread_variable_set(:master_fix_settings_owner, Fiber.current)
          begin
            yield
          ensure
            Thread.current.thread_variable_set(:master_fix_settings_owner, nil)
          end
        end
      end

      GENESIS = "0" * 64
      LOG_RELATIVE_PATH = ".master/log.jsonl"

      class LedgerCorruption < StandardError; end

      # The Kernel owns coordinator receipts only. FixLoop/RepairLoop and
      # Transaction remain the sole repository-mutation path.
      def initialize(root:, actor: "fix", bus: nil, log_path: nil, lifecycle_journal: nil)
        @root = File.expand_path(root)
        @workspace_root = self.class.send(:locate_workspace, @root)
        @actor = actor.to_s
        @bus = bus
        @state_root = MasterPaths.fix_state(root: @workspace_root)
        @log_path = File.expand_path(log_path || File.join(@state_root, File.basename(LOG_RELATIVE_PATH)))
        @log_head = nil
        @lifecycle_journal = lifecycle_journal
        @lifecycle_mutex = Mutex.new
        @execution_mutex = ExecutionLock.new(root: @workspace_root, state_root: @state_root)
        @append_mutex = Mutex.new
      end

      attr_reader :root, :workspace_root, :actor, :log_path, :execution_mutex

      # The one validated execution door. The adapter is injected because boot
      # owns the live agent/scanner/law dependencies; Kernel owns the contract
      # scope, process lock and terminal lifecycle. Validation happens before
      # acquiring the lock or starting a run receipt.
      def run(adapter:, contract:, target:, max_passes:, budget_seconds:, incremental:,
              requested:, cancellation: nil)
        if production_host?
          raise TaskContract::Invalid,
                "/fix is disabled on production vm23; run repairs, scans and tests on the development workstation"
        end
        raise TaskContract::Invalid, "Kernel#run requires a TaskContract" if contract.nil?

        validated = TaskContract.coerce(contract)
        unless validated.instance_of?(TaskContract::Contract)
          raise TaskContract::Invalid, "Kernel#run requires a validated TaskContract::Contract"
        end

        TaskContract.with_current(validated) do
          run_fix_loop(
            adapter, target:, max_passes:, budget_seconds:, incremental:,
            requested:, cancellation:
          )
        end
      end

      # Return the verified terminal projection for one completed attempt.
      # A missing terminal row means the run has not finished; callers must not
      # manufacture a success receipt from an open or interrupted run.
      def terminal_receipt(run_id:, attempt_id: nil)
        identifier = run_id.to_s
        raise ArgumentError, "terminal receipt requires a run ID" if identifier.empty?

        events = verify_log!
        terminal = find_terminal_event(events, identifier, attempt_id)
        return unless terminal

        started = find_attempt_start(events, identifier, terminal)
        raise LedgerCorruption, "terminal event has no matching coordinator start" unless started

        journal_run = lifecycle_journal.history.find { |row| row["id"] == identifier }
        TerminalReceipt.build(
          start_event: started,
          terminal_event: terminal,
          repair_events: attempt_repairs(events, identifier, started, terminal),
          journal_run:,
          assessment: attempt_assessment(journal_run, identifier)
        )
      end

      def self.replay_events(root:, seq:)
        number = Integer(seq)
        raise ArgumentError, "sequence must be a positive integer" unless number.positive?

        workspace = locate_workspace(File.expand_path(root))
        path = File.join(MasterPaths.fix_state(root: workspace), File.basename(LOG_RELATIVE_PATH))
        events = read_log(path)
        selected = events.find { |row| row.fetch("seq") == number }
        return unless selected

        run_id = selected["run_id"]
        run_events = run_id ? events.select { |row| row["run_id"] == run_id } : [selected]
        { "sequence" => number, "run_id" => run_id, "events" => run_events }
      end

      def self.replay_cli(root:, seq:)
        unless seq && seq.match?(/\A[1-9][0-9]*\z/)
          warn "master0: usage master replay sequence"
          return 64
        end

        result = replay_events(root:, seq:)
        unless result
          warn "master0: replay sequence not found"
          return 1
        end

        puts JSON.pretty_generate(result)
        0
      rescue LedgerCorruption => error
        warn "master0: audit log corrupt, #{error.message}"
        1
      rescue StandardError => error
        warn "master0: replay failed, #{error.class}: #{error.message}"
        1
      end

      def self.locate_workspace(path)
        cursor = path
        loop do
          return cursor if File.exist?(File.join(cursor, ".git"))

          parent = File.dirname(cursor)
          return path if parent == cursor

          cursor = parent
        end
      end

      private

      # Defence in depth for every programmatic caller, including callers that
      # bypass TurnRouter and the fix-here terminal wrapper.
      def production_host?
        return true if ENV["PUB5_PRODUCTION_HOST"] == "1"
        return false unless RUBY_PLATFORM.match?(/openbsd/i)

        File.file?("/etc/master.env") && File.directory?("/home/dev/pub5/MASTER")
      rescue SystemCallError
        false
      end

      # The most recent coordinator_terminal row for the run, optionally
      # narrowed to one attempt.
      def find_terminal_event(events, identifier, attempt_id)
        events.reverse.find do |row|
          next false unless row["kind"] == "coordinator_terminal" && row["run_id"] == identifier

          attempt_id.nil? || row.dig("payload", "attempt_id").to_s == attempt_id.to_s
        end
      end

      def find_attempt_start(events, identifier, terminal)
        selected_attempt = terminal.dig("payload", "attempt_id").to_s
        events.find do |row|
          row["kind"] == "coordinator_started" &&
            row["run_id"] == identifier &&
            row.dig("payload", "attempt_id").to_s == selected_attempt
        end
      end

      # Only evidence inside the completed attempt's ledger prefix belongs
      # to its receipt. A later row carrying a stale run ID must not rewrite
      # the meaning of an already-terminal attempt.
      def attempt_repairs(events, identifier, started, terminal)
        selected_attempt = terminal.dig("payload", "attempt_id").to_s
        events.select do |row|
          sequence = row.fetch("seq").to_i
          row["kind"] == "repair_pass" &&
            row["run_id"] == identifier &&
            row.dig("payload", "attempt_id").to_s == selected_attempt &&
            sequence > started.fetch("seq").to_i &&
            sequence < terminal.fetch("seq").to_i
        end
      end

      def attempt_assessment(journal_run, identifier)
        if journal_run && journal_run["assessment_receipt"].is_a?(Hash)
          lifecycle_journal.verify_assessment_report(identifier)
        else
          { "status" => "receipt_missing" }
        end
      end

      private_class_method :locate_workspace
    end
  end
end
