# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "securerandom"
require_relative "../io/atomic_write"
require_relative "../core/world"
require_relative "../trace/mutation_observer"
require_relative "task_contract"
require_relative "transaction/delivery"
require_relative "transaction/recovery"
# The class is split by concern; these three re-open Master::Fix::Transaction
# and are registered in data/autoload.yml under reopens_a_constant_defined_elsewhere.
require_relative "transaction/validation"
require_relative "transaction/observation"
require_relative "transaction/delivery_door"

module Master
  module Fix
    # Disk-backed pass transaction for /fix.
    #
    # Snapshots live outside the Ruby heap and carry their own lifecycle marker.
    # An interrupted transaction in the "open" state can therefore be restored
    # on the next invocation; "delivering" means Git delivery may already have
    # started, so recovery preserves the tree and lets /fix re-observe it.
    class Transaction
      include ::Master::Io::AtomicWrite

      Snapshot = Data.define(:path, :exists, :kind, :mode, :link, :store)

      ROOT_DIR = ".master/fix_transactions"
      LOCK = ".master/fix_transaction.lock"
      MANIFEST = "manifest.json"
      DELIVERY_FIELDS = %i[state active head_before head_after marked].freeze

      def self.normalize_id(id)
        value = id.to_s
        raise ArgumentError, "transaction id is unsafe" unless value.match?(%r{\A[a-zA-Z0-9_-]+\z})

        value
      end
      private_class_method :normalize_id

      def initialize(root:, paths:, id: SecureRandom.hex(10), bus: nil)
        @root = File.expand_path(root)
        @paths = Array(paths).map { |path| normalize(path) }
        raise "transaction contains an unsafe path" if @paths.any?(&:nil?)
        @paths.uniq!
        validate_task_contract_paths!(@paths)
        @id = self.class.send(:normalize_id, id)
        @bus = bus
        @lifecycle_observer = Master::Trace::MutationObserver.new(
          root: @root, namespace: "fix:transaction_lifecycle",
          subject_type: "transaction", subject_id: @id, bus: @bus
        )
        @pending_marker_owned = false
        @seen = Hash.new { |hash, path| hash[path] = [] }
        @snapshots = {}
        @snapshot_fingerprints = {}
        @dir = File.join(@root, ROOT_DIR, @id)
        @lock = nil
        @active = false
        @state = "new"
      end

      def begin!
        raise "transaction already active" if @active
        created_dir = false
        acquire_lock
        raise "transaction id already exists: #{@id}" if File.exist?(@dir) || File.symlink?(@dir)

        lifecycle_mutation(:begin, item_count: @paths.size) do
          Dir.mkdir(@dir, 0o700)
          created_dir = true
          open_transaction!
        end
      rescue StandardError
        @active = false
        if pending_marker? || persisted? || !created_dir
          release_lock
        else
          cleanup!
          release_lock
        end
        raise
      end

      # Move the rollback floor after a commit has been pushed. The logical
      # pass transaction stays alive, but an interruption can no longer roll a
      # previously delivered checkpoint back to the pass-start snapshot.
      def checkpoint!(paths)
        raise "transaction not active" unless @active

        selected = checkpoint_paths(paths)
        lifecycle_mutation(:checkpoint, item_count: selected.size) do
          staged = selected.to_h { |path| [path, snapshot(path, versioned: true)] }
          verdict = checkpoint_verdict(selected, staged)
          if verdict.nil?
            old = [@snapshots, @seen, @state, @delivery_head_before, @delivery_head_after, @delivery_marked]
            commit_checkpoint(selected, staged)
          else
            verdict
          end
        end
      rescue StandardError => e
        raise if @lifecycle_observer.failed?

        undo_checkpoint(old) if defined?(old) && !persisted_state_matches?
        emit("fix:transaction_checkpoint_failed", id: @id, error: e.message)
        Result.err("transaction checkpoint: #{e.class}", category: :infrastructure)
      end

      def finalize!
        raise "transaction not active" unless @active

        lifecycle_mutation(:finalize, item_count: @paths.size) do
          @state = "committed"
          @active = false
          persist!
          Result.ok(@paths)
        end
        cleanup!
        release_lock
        emit("fix:transaction_commit", id: @id, paths: @paths)
        Result.ok(@paths)
      rescue StandardError => e
        emit("fix:transaction_commit_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction finalize: #{e.class}", category: :infrastructure)
      end

      def rollback!
        # A committed pass is delivered work; undoing it is a new change, never a rollback.
        if %w[committed rolled_back].include?(@state)
          return Result.err("rollback refused: transaction already #{@state.tr("_", " ")}", category: :policy)
        end
        raise "transaction not active" unless @active || persisted?
        return delivery.preserve! if @state == "delivering" && delivery.pending?

        result = lifecycle_mutation(:rollback, item_count: @paths.size) { settle_rollback }
        finish_rollback(result)
      rescue StandardError => e
        emit("fix:transaction_rollback_failed", id: @id, error: e.message)
        @active = false
        release_lock
        Result.err("transaction rollback: #{e.class}", category: :infrastructure)
      end

      # Releases the root lock, first removing the transaction directory when asked.
      def close!(cleanup: false)
        cleanup! if cleanup
        release_lock
      end

      def id = @id
      def root = @root
      def state = @state
      def active? = @active

      private

      # begin!'s mutation leg once the directory exists: snapshot every path,
      # flip to open, and announce. Answers self, so begin! still returns it.
      def open_transaction!
        @paths.each do |path|
          @snapshots[path] = snapshot(path)
          raise "transaction cannot safely track unsupported filesystem object" if @snapshots[path].kind == :other
        end
        @state = "open"
        @active = true
        observe!(verify_snapshot: true)
        emit("fix:transaction_snapshot_summary", id: @id, tracked_paths: @paths.size)
        emit("fix:transaction_start", id: @id, paths: @paths)
        self
      end

      # checkpoint!'s admission leg: canonical paths this transaction tracks.
      def checkpoint_paths(paths)
        selected = Array(paths).map { |path| normalize(path) }
        raise "checkpoint includes an unsafe path" if selected.any?(&:nil?)
        selected = selected.uniq
        raise "checkpoint includes a path outside the transaction" unless (selected - @paths).empty?

        selected
      end

      # checkpoint!'s verdict leg: an unsupported directory or a source that
      # moved under the transaction refuses before anything is merged.
      def checkpoint_verdict(selected, staged)
        return Result.err("checkpoint cannot safely capture a directory", category: :policy) if staged.values.any? { |item| item.kind == :other }
        return Result.err("transaction source changed while checkpointing", category: :policy) unless
          selected.all? { |path| snapshot_matches_fingerprint?(staged.fetch(path), fingerprint(absolute(path))) }

        nil
      end

      # checkpoint!'s commit leg: merge the versioned snapshots, reset the
      # observation floor for the checked paths, persist, then drop stores no
      # snapshot references any more.
      def commit_checkpoint(selected, staged)
        old_stores = selected.filter_map { |path| @snapshots[path]&.store }
        @snapshots = @snapshots.merge(staged)
        @seen = @seen.to_h.transform_values(&:dup)
        @seen.default_proc = ->(hash, path) { hash[path] = [] }
        selected.each { |path| @seen[path] = [fingerprint(absolute(path))] }
        @state = "open"
        @delivery_head_before = @delivery_head_after = nil
        persist!
        release_checkpoint_stores(old_stores)
        emit("fix:transaction_checkpoint", id: @id, paths: selected)
        Result.ok(selected)
      end

      # A replaced checkpoint orphans the previous store file; delete it once
      # no snapshot still references it.
      def release_checkpoint_stores(stores)
        stores.each do |store|
          next unless store

          File.delete(store) unless @snapshots.values.any? { |item| item.store == store }
        end
      end

      # A crash mid-commit rolls the memory image back to the pre-checkpoint
      # floor unless the persisted manifest already matches it.
      def undo_checkpoint(old)
        @snapshots, @seen, @state, @delivery_head_before, @delivery_head_after, @delivery_marked = old
      end

      # rollback!'s mutation leg: a delivering pass reopens, then either
      # restores every snapshot or refuses on a concurrent change.
      def settle_rollback
        @state = "open" if @state == "delivering"
        @delivery_head_before = nil if @state == "open"
        current_conflicts = conflicts()
        current_conflicts.empty? ? restore_snapshots_and_roll_back : reject_rollback_conflict(current_conflicts)
      end

      # rollback!'s terminal bookkeeping: a rolled-back pass drops its
      # directory and lock, a conflicted one keeps them for review.
      def finish_rollback(result)
        if @state == "rolled_back"
          cleanup!
          @active = false
          release_lock
          emit("fix:transaction_rollback", id: @id, paths: @paths)
        elsif @state == "conflict"
          @active = false
          release_lock
          emit("fix:transaction_conflict", id: @id, paths: @paths)
        end
        result
      end

      def reject_rollback_conflict(conflicts)
        @state = "conflict"
        persist!
        Result.err("rollback refused: concurrent changes in #{conflicts.size} path(s)", category: :policy)
      end

      def restore_snapshots_and_roll_back
        @snapshots.each { |path, snap| restore(path, snap) }
        @state = "rolled_back"
        persist!
        Result.ok(@paths)
      end

      def lifecycle_mutation(operation, item_count: nil)
        @lifecycle_observer.mutate(operation:, item_count:) do
          create_pending_marker!(operation)
          yield
        end.tap do
          remove_pending_marker! if @pending_marker_owned
        end
      rescue StandardError
        recover_lifecycle_audit
        raise
      end

      # lifecycle_mutation's failure leg: an audit failure marks the
      # transaction trace_failed and persists that fact; otherwise the
      # caller's pending marker is removed. Either way the error propagates.
      def recover_lifecycle_audit
        if @lifecycle_observer.failed?
          @state = "trace_failed"
          begin
            persist! if persisted?
          rescue StandardError
            nil
          end
        elsif @pending_marker_owned
          begin
            remove_pending_marker!
          rescue StandardError
            nil
          end
        end
      end

      # Transaction events are diagnostic telemetry, not the durable manifest.
      # Never persist raw workspace paths or free-form errors/results here: paths
      # live in the protected transaction manifest, and actionable errors remain
      # in the local Result/exception for the operator.
      def emit(event, **payload)
        safe = payload.dup
        if safe.key?(:paths)
          paths = Array(safe.delete(:paths)).map(&:to_s).sort
          safe[:paths_count] = paths.size
          safe[:paths_digest] = Digest::SHA256.hexdigest(paths.join("\0"))
        end

        %i[error result message detail output].each do |key|
          value = safe.delete(key)
          next unless value.is_a?(String)

          safe["#{key}_digest".to_sym] = Digest::SHA256.hexdigest(value)
          safe["#{key}_bytes".to_sym] = value.bytesize
        end
        safe[:schema_version] = 1 unless safe.key?(:schema_version)
        @bus&.publish(event, **safe)
      rescue StandardError => e
        warn("trace0: #{e.class}: event publication failed") if ENV["MASTER_TRACE_STRICT"] == "1"
        nil
      end

      def acquire_lock(nonblock: false)
        master_dir = File.join(@root, ".master")
        tx_root = File.join(@root, ROOT_DIR)
        raise "MASTER state directory is a symlink" if File.symlink?(master_dir)
        raise "transaction root is a symlink" if File.symlink?(tx_root)
        FileUtils.mkdir_p(tx_root)
        path = File.join(@root, LOCK)
        raise "transaction lock path is a symlink" if File.symlink?(path)
        @lock = File.open(path, File::RDWR | File::CREAT, 0o600)
        locked = @lock.flock(File::LOCK_EX | (nonblock ? File::LOCK_NB : 0))
        release_lock unless locked
        !!locked
      rescue StandardError
        release_lock
        raise
      end

      def release_lock
        return unless @lock

        @lock.flock(File::LOCK_UN)
        @lock.close
        @lock = nil
      end
    end
  end
end
