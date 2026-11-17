# frozen_string_literal: true

module Master
  module Fix
    class Transaction
      # The write path's eyes, re-opening the class defined in
      # fix/transaction.rb: observation, enlistment, conflict release, and the
      # snapshot machinery they stand on, plus the path sandbox every disk
      # access goes through. Public here is still public Transaction API; the
      # private helpers serve it.
      def observe!(verify_snapshot: false)
        @paths.each do |path|
          current = fingerprint(absolute(path))
          if verify_snapshot && @snapshot_fingerprints.fetch(path) != current
            raise "transaction source changed during initial snapshot: #{path}"
          end
          @seen[path] << current
          @seen[path] = @seen[path].uniq.last(8)
        end
        persist! if @active
        true
      end

      # Add a narrowly approved related artifact to this transaction before
      # its first write, so rollback and interrupted-run recovery keep its bytes.
      def enlist!(paths)
        raise "transaction not active" unless @active

        added = enlistable_paths(paths)
        staged = added.to_h { |path| [path, snapshot(path)] }
        return Result.err("transaction source changed during enlistment", category: :policy) unless
          added.all? { |path| snapshot_matches_fingerprint?(staged.fetch(path), fingerprint(absolute(path))) }

        old = [@paths, @snapshots]
        @snapshots = @snapshots.merge(staged)
        @paths = (@paths + added).uniq
        observed = observe_paths!(added) unless added.empty?
        return enlist_observed_rollback(observed, old) if observed&.err?

        emit("fix:transaction_paths_enlisted", id: @id, paths: added)
        Result.ok(added)
      rescue TaskContract::Invalid => e
        enlist_failed(e.message, "transaction enlistment refused: #{e.message}", :policy)
      rescue StandardError => e
        enlist_failed(e.message, "transaction enlistment: #{e.message}", :infrastructure)
      end

      # Refresh only explicitly enlisted paths after the transaction's own
      # verified write. Unrelated files retain their original concurrency guard.
      def observe_paths!(paths)
        raise "transaction not active" unless @active

        selected = Array(paths).map { |path| normalize(path) }
        raise "observation includes an unsafe path" if selected.any?(&:nil?)
        selected = selected.uniq
        raise "observation includes a path outside the transaction" unless (selected - @paths).empty?

        old_seen = @seen
        @seen = @seen.to_h.transform_values(&:dup).tap { |seen| seen.default_proc = ->(hash, path) { hash[path] = [] } }
        selected.each do |path|
          @seen[path] << fingerprint(absolute(path))
          @seen[path] = @seen[path].uniq.last(8)
        end
        persist!
        emit("fix:transaction_paths_observed", id: @id, paths: selected)
        Result.ok(selected)
      rescue StandardError => e
        @seen = old_seen if defined?(old_seen) && !persisted_state_matches?
        emit("fix:transaction_observe_failed", id: @id, error: e.message)
        Result.err("transaction observation: #{e.message}", category: :infrastructure)
      end

      def observed_current?(path)
        relative = normalize(path)
        return false unless relative && @paths.include?(relative)

        expected = @seen[relative].last
        expected && expected == fingerprint(absolute(relative))
      rescue StandardError
        false
      end

      # A delivery caller can bind Git's private-index commit to the exact bytes
      # this transaction last observed. A fresh digest of the worktree alone
      # would bless a concurrent writer's replacement.
      def observed_content_hash(path)
        relative = normalize(path)
        return unless relative && @paths.include?(relative)

        value = @seen[relative].last
        value.delete_prefix("file:") if value&.start_with?("file:")
      end

      def snapshot_content_hash(path)
        relative = normalize(path)
        return unless relative && @paths.include?(relative)

        value = @snapshot_fingerprints[relative]
        value.delete_prefix("file:") if value&.start_with?("file:")
      end

      # The paths among these that this transaction tracks, in its own spelling.
      def tracked(paths) = Array(paths).filter_map { |path| normalize(path) } & @paths

      # Stops tracking paths that changed under the pass without its write: they are neither
      # delivered nor rolled back, so another writer's work stays as that writer left it.
      def release!(paths)
        released = Array(paths).filter_map { |path| normalize(path) } & @paths
        return [] if released.empty?

        lifecycle_mutation(:release, item_count: released.size) do
          @paths -= released
          released.each { |path| @snapshots.delete(path) && @seen.delete(path) }
          persist!
          emit("fix:transaction_release", id: @id, paths: released)
          released
        end
      end

      def conflicts
        @paths.reject { |path| @seen.fetch(path, []).include?(fingerprint(absolute(path))) }
      end

      # Before a rollback of an open pass: another writer's edits leave the transaction, so the
      # rollback restores the pass's own writes and leaves theirs. Answers the paths released.
      def release_conflicts!
        return [] unless @active && @state == "open"

        release!(conflicts)
      end

      private

      # enlist!'s admission leg: canonical paths, unsafe ones refused, then
      # the task contract applied; answers the paths not already tracked.
      def enlistable_paths(paths)
        selected = Array(paths).map { |path| normalize(path) }
        raise "transaction enlistment contains an unsafe path" if selected.any?(&:nil?)
        validate_task_contract_paths!(selected)

        selected.uniq - @paths
      end

      def enlist_failed(message, refusal, category)
        emit("fix:transaction_enlist_failed", id: @id, error: message)
        Result.err(refusal, category:)
      end

      # An observation failure after staging rolls the in-memory enlistment
      # back unless the persisted manifest already shows it.
      def enlist_observed_rollback(observed, old)
        @paths, @snapshots = old unless persisted_state_matches?
        observed
      end

      def snapshot(path, versioned: false)
        abs = absolute(path)
        unless File.exist?(abs) || File.symlink?(abs)
          @snapshot_fingerprints[path] = "missing"
          return Snapshot.new(path, false, :missing, nil, nil, nil)
        end

        stat = File.lstat(abs)
        if stat.symlink?
          link = File.readlink(abs)
          @snapshot_fingerprints[path] = "symlink:#{stat.mode}:#{link}"
          Snapshot.new(path, true, :symlink, stat.mode & 0o7777, link, nil)
        elsif stat.file?
          name = encoded(path)
          name = "#{name}.#{SecureRandom.hex(8)}" if versioned
          store = File.join(@dir, "files", name)
          @snapshot_fingerprints[path] = snapshot_file(abs, store)
          Snapshot.new(path, true, :file, stat.mode & 0o7777, nil, store)
        else
          @snapshot_fingerprints[path] = "other:#{stat.mode}:#{stat.size}"
          Snapshot.new(path, true, :other, stat.mode & 0o7777, nil, nil)
        end
      end

      def snapshot_file(source, destination)
        raise "transaction snapshot storage is a symlink" if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, "files")].any? { |path| File.symlink?(path) }
        FileUtils.mkdir_p(File.dirname(destination))
        temporary = "#{destination}.tmp.#{Process.pid}.#{SecureRandom.hex(4)}"
        digest = Digest::SHA256.new
        File.open(source, "rb") do |input|
          File.open(temporary, "wb", 0o600) do |output|
            while (chunk = input.read(1024 * 1024))
              digest.update(chunk)
              output.write(chunk)
            end
            output.flush
            output.fsync
          end
        end
        File.rename(temporary, destination)
        "file:#{digest.hexdigest}"
      ensure
        File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
      end

      def fingerprint(path)
        return "missing" unless File.exist?(path) || File.symlink?(path)

        stat = File.lstat(path)
        return "symlink:#{stat.mode}:#{File.readlink(path)}" if stat.symlink?
        return "other:#{stat.mode}:#{stat.size}" unless stat.file?

        "file:#{Digest::SHA256.file(path)}"
      rescue StandardError => e
        "error:#{e.class}:#{e.message}"
      end

      def snapshot_matches_fingerprint?(snapshot, current)
        return current == "missing" if snapshot.kind == :missing
        return current == fingerprint(snapshot.store) if snapshot.kind == :file

        snapshot.kind == :symlink && current.start_with?("symlink:") && current.split(":", 3).last == snapshot.link
      rescue StandardError
        false
      end

      def normalize(path)
        value = path.to_s
        return if value.empty?

        full = File.expand_path(value, @root)
        return unless inside?(full, File.expand_path(@root)) || inside?(full, outer_root)

        Pathname.new(full).relative_path_from(File.expand_path(@root)).to_s
      end

      # A /fix run rooted in MASTER may repair a RAILS or OPENBSD file beside it: the transaction
      # snapshots and restores any file in the repository MASTER sits in, named relative to MASTER.
      def outer_root
        return File.expand_path(@root) unless defined?(Master::REPO_ROOT)

        repo = File.expand_path(Master::REPO_ROOT)
        inside?(File.expand_path(@root), repo) ? repo : File.expand_path(@root)
      end

      def inside?(path, dir) = path == dir || path.start_with?(dir + File::SEPARATOR)

      def absolute(path) = path_guard.within(File.join(@root, path))
      def path_guard = (@path_guard ||= Master::Core::World.new(root: outer_root))
    end
  end
end
