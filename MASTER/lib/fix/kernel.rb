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

module Master
  module Fix
    # Owns the hash-chained /fix coordinator lifecycle and keeps the replay
    # reader public for `bin/master replay <seq>`. It does not apply repairs;
    # FixLoop, RepairAdapter and Transaction retain the mutation responsibilities.
    # A broken chain is refused rather than returned as partial history.
    # The ledger itself (append, verified read, verify reader) re-opens this
    # class from kernel/ledger.rb.
    class Kernel
      public

      # The hash-chained ledger, re-opening the Kernel defined in
      # fix/kernel.rb: the append path (append_event) with its TOCTOU-checked
      # directory, path and handle validation, the verified read path
      # (read_log/read_log_io) behind `bin/master replay`, and the instance
      # verify_log! reader the lifecycle mutators consult before writing.
      # Every append serializes on @append_mutex and fsyncs before returning.
      def verify_log!
        self.class.read_log(@log_path)
      end

      def append_event(kind, payload, run_id: nil)
        @append_mutex.synchronize do
          assert_writable_ledger_directory!
          assert_private_ledger_path!
          open_ledger_for_append do |file|
            opened_stat = assert_open_ledger_handle!(file)
            raise IOError, "could not acquire ledger append lock" unless file.flock(File::LOCK_EX)

            assert_unchanged_ledger_path!("ledger path changed while waiting for its lock", opened: opened_stat)
            row = build_ledger_row(kind, payload, run_id, append_head(file))
            write_ledger_row!(file, row)
            row
          ensure
            file.flock(File::LOCK_UN) rescue nil
          end
        end
      end

      def self.read_log(path)
        expanded = File.expand_path(path)
        assert_readable_log_directory!(expanded)
        return [] unless File.exist?(expanded) || File.symlink?(expanded)

        assert_readable_log_file!(expanded)
        File.open(expanded, log_read_flags) do |file|
          opened = opened_log_stat!(file, expanded)
          events = read_log_io(file)
          assert_unmodified_log!(expanded, opened)
          events
        end
      rescue SystemCallError => error
        raise LedgerCorruption, "audit log cannot be opened safely: #{error.class}: #{error.message}"
      end

      # Every record must carry the next sequence number, the previous
      # record's hash and its own body hash; any gap, edit or torn final line
      # is corruption.
      def self.read_log_io(file)
        previous = GENESIS
        expected_seq = 1
        events = []

        file.rewind
        file.each_line.with_index(1) do |line, line_number|
          row = verified_log_row(line, line_number, previous, expected_seq)
          events << row
          previous = row.fetch("hash")
          expected_seq += 1
        end
        events
      end

      def self.verified_log_row(line, line_number, previous, expected_seq)
        raise LedgerCorruption, "line #{line_number}: incomplete final record" unless line.end_with?("\n")
        raise LedgerCorruption, "line #{line_number}: blank record" if line.strip.empty?

        row = JSON.parse(line)
        body = row.reject { |key, _| key == "hash" }
        raise LedgerCorruption, "line #{line_number}: sequence gap" unless row.fetch("seq") == expected_seq
        raise LedgerCorruption, "line #{line_number}: previous hash mismatch" unless row.fetch("prev") == previous
        actual = Digest::SHA256.hexdigest(JSON.generate(body))
        raise LedgerCorruption, "line #{line_number}: event hash mismatch" unless actual == row.fetch("hash")

        row
      rescue JSON::ParserError, KeyError, TypeError, NoMethodError => error
        raise LedgerCorruption, "line #{line_number}: #{error.message}"
      end

      # The audit log's parent directory must be an existing, real, private
      # directory. A missing directory makes a missing log simply absent, but
      # never hides a log that exists without it.
      def self.assert_readable_log_directory!(expanded)
        directory = File.dirname(expanded)
        if File.exist?(directory) || File.symlink?(directory)
          directory_stat = File.lstat(directory)
          unless directory_stat.directory? && !directory_stat.symlink?
            raise LedgerCorruption, "refusing non-directory or symlinked audit log directory"
          end
          if (directory_stat.mode & 0o022).positive?
            raise LedgerCorruption, "audit log directory is group/world writable"
          end
        elsif File.exist?(expanded) || File.symlink?(expanded)
          raise LedgerCorruption, "audit log exists without its parent directory"
        end
      end

      def self.assert_readable_log_file!(expanded)
        path_stat = File.lstat(expanded)
        unless path_stat.file? && !path_stat.symlink? && path_stat.nlink == 1
          raise LedgerCorruption, "refusing symlinked, hard-linked or non-regular audit log"
        end
        if (path_stat.mode & 0o077).positive?
          raise LedgerCorruption, "audit log permissions must be private (0600 or stricter)"
        end
      end

      def self.log_read_flags
        unless File.const_defined?(:NOFOLLOW)
          raise LedgerCorruption, "O_NOFOLLOW is required for safe audit-log reads on this platform"
        end

        File::RDONLY | File::NOFOLLOW
      end

      # Between open and read the path must still lstat to the same singly
      # linked regular file. Returns the opened stat the completion check
      # compares against.
      def self.opened_log_stat!(file, expanded)
        opened = file.stat
        current = File.lstat(expanded)
        unless current.file? && !current.symlink? && current.nlink == 1 &&
               current.dev == opened.dev && current.ino == opened.ino
          raise LedgerCorruption, "audit log path changed while opening"
        end
        opened
      end

      def self.assert_unmodified_log!(expanded, opened)
        after = File.lstat(expanded)
        unless after.file? && !after.symlink? && after.nlink == 1 &&
               after.dev == opened.dev && after.ino == opened.ino &&
               after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
          raise LedgerCorruption, "audit log changed while reading"
        end
      end

      private

      def append_head(file)
        stat = file.stat
        cached = @log_head
        if cached
          unless stat.dev == cached.fetch(:dev) && stat.ino == cached.fetch(:ino) &&
                 stat.size >= cached.fetch(:size)
            raise LedgerCorruption, "ledger identity changed or ledger was truncated"
          end
          return revalidated_log_head(file, cached) if stat.size > cached.fetch(:size)
          return cached if stat.mtime == cached.fetch(:mtime) && stat.ctime == cached.fetch(:ctime)
        end

        events = self.class.send(:read_log_io, file)
        last = events.last
        cache_log_head(file, last ? last.fetch("seq") : 0, last ? last.fetch("hash") : GENESIS)
      end

      def revalidated_log_head(file, _cached)
        # A different writer may have appended, but suffix-only validation
        # trusts the cached prefix without proving that its bytes survived.
        # Re-validate the complete chain before adopting the new head.
        events = self.class.send(:read_log_io, file)
        last = events.last
        cache_log_head(file, last ? last.fetch("seq") : 0, last ? last.fetch("hash") : GENESIS)
      end

      def cache_log_head(file, seq, hash)
        stat = file.stat
        @log_head = {
          dev: stat.dev, ino: stat.ino, size: stat.size,
          mtime: stat.mtime, ctime: stat.ctime, seq:, hash:
        }
      end

      # The ledger directory must be a private real directory before the log
      # path itself is touched.
      def assert_writable_ledger_directory!
        directory = File.dirname(@log_path)
        raise LedgerCorruption, "ledger directory is a symlink" if File.symlink?(directory)

        FileUtils.mkdir_p(directory, mode: 0o700)
        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink?
          raise LedgerCorruption, "ledger directory is not a real directory"
        end
        raise LedgerCorruption, "ledger directory is group/world writable" if
          (directory_stat.mode & 0o022).positive?
      end

      def assert_private_ledger_path!
        raise LedgerCorruption, "ledger path is a symlink" if File.symlink?(@log_path)

        return unless File.exist?(@log_path)

        path_stat = File.lstat(@log_path)
        raise LedgerCorruption, "ledger path is not a regular file" unless
          path_stat.file? && !path_stat.symlink?
        raise LedgerCorruption, "ledger permissions are not private" unless
          (path_stat.mode & 0o077).zero?
      end

      # Create a missing ledger exclusively so a competing first writer cannot
      # plant a pre-seeded path between the absence check and open. If another
      # legitimate writer wins, validate the now-existing path before reopening.
      def open_ledger_for_append(&block)
        if File.exist?(@log_path) || File.symlink?(@log_path)
          assert_private_ledger_path!
          return File.open(@log_path, ledger_open_flags, 0o600, &block)
        end

        begin
          File.open(@log_path, ledger_open_flags(exclusive: true), 0o600, &block)
        rescue Errno::EEXIST
          # Another first writer won. Re-validate its object before using it.
          assert_private_ledger_path!
          File.open(@log_path, ledger_open_flags, 0o600, &block)
        end
      end

      def ledger_open_flags(exclusive: false)
        unless File.const_defined?(:NOFOLLOW)
          raise LedgerCorruption, "O_NOFOLLOW is required for safe audit-ledger appends on this platform"
        end

        flags = File::RDWR | File::CREAT | File::APPEND | File::NOFOLLOW
        flags |= File::EXCL if exclusive
        flags
      end

      # The freshly opened handle must still be the canonical private ledger
      # path; returns the opened stat the post-flock check re-compares.
      def assert_open_ledger_handle!(file)
        opened_stat = file.stat
        raise LedgerCorruption, "ledger handle is not a regular file" unless opened_stat.file?
        raise LedgerCorruption, "ledger permissions are not private" unless
          (opened_stat.mode & 0o077).zero?
        raise LedgerCorruption, "refusing hard-linked audit ledger" unless opened_stat.nlink == 1
        assert_unchanged_ledger_path!("ledger path changed while opening", opened: opened_stat)
        opened_stat
      end

      def assert_unchanged_ledger_path!(message, opened:)
        current_stat = File.lstat(@log_path)
        return if current_stat.file? && !current_stat.symlink? && current_stat.nlink == 1 &&
                  current_stat.dev == opened.dev && current_stat.ino == opened.ino

        raise LedgerCorruption, message
      end

      def build_ledger_row(kind, payload, run_id, head)
        body = {
          "seq" => head.fetch(:seq) + 1, "at" => Time.now.utc.iso8601(6),
          "run_id" => run_id, "kind" => kind.to_s, "payload" => payload,
          "prev" => head.fetch(:hash)
        }
        body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
      end

      def write_ledger_row!(file, row)
        stat = file.stat
        unless stat.file? && stat.nlink == 1
          raise LedgerCorruption, "refusing to append through a non-regular or hard-linked ledger handle"
        end
        assert_unchanged_ledger_path!("ledger path changed before append", opened: stat)
        line = JSON.generate(row) + "\n"
        file.seek(0, IO::SEEK_END)
        written = file.write(line)
        raise IOError, "ledger append wrote #{written || 0} of #{line.bytesize} bytes" unless
          written == line.bytesize

        file.flush
        file.fsync
        cache_log_head(file, row.fetch("seq"), row.fetch("hash"))
      end

      private_class_method :read_log_io, :verified_log_row,
                           :assert_readable_log_directory!, :assert_readable_log_file!,
                           :log_read_flags, :opened_log_stat!, :assert_unmodified_log!

      public

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
