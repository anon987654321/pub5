# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Durable state persistence on the run journal: the inter-process journal
      # lock, TOCTOU-checked state reads and atomic writes with pending-marker
      # recovery, and creation of the private state directory itself.
      class LifecycleJournal
        MARKER_INCOMPLETE = "fix journal lifecycle audit is incomplete; manual review required"

        private

        # Verify the state directory exists, is a private real directory, and
        # create any missing ancestors on the way down. Returns the root.
        def ensure_state_directory!
          root = File.expand_path(@state_root)
          missing, cursor = existing_state_ancestor(root)
          stat = File.lstat(cursor)
          unless stat.directory? && !stat.symlink?
            raise IOError, "refusing non-directory or symlinked fix state parent"
          end

          create_missing_state_directories!(missing)
          final = File.lstat(root)
          unless final.directory? && !final.symlink? && (final.mode & 0o022).zero?
            raise IOError, "refusing unsafe fix state directory"
          end
          enforce_state_root_privacy!(root, final)
          root
        rescue SystemCallError => error
          raise IOError, "cannot prepare persistent fix state safely: #{error.class}: #{error.message}"
        end

        def existing_state_ancestor(root)
          missing = []
          cursor = root
          until File.exist?(cursor) || File.symlink?(cursor)
            missing.unshift(cursor)
            parent = File.dirname(cursor)
            raise IOError, "fix state has no existing parent directory" if parent == cursor

            cursor = parent
          end
          [missing, cursor]
        end

        def create_missing_state_directories!(missing)
          missing.each do |directory|
            Dir.mkdir(directory, 0o700)
            created = File.lstat(directory)
            unless created.directory? && !created.symlink? && (created.mode & 0o077).zero?
              raise IOError, "new fix state directory is not private"
            end
          end
        end

        def enforce_state_root_privacy!(root, final)
          return if @local_state_root || (final.mode & 0o077).zero?

          if File.owned?(root)
            File.chmod(0o700, root)
          else
            raise IOError, "persistent fix state directory permissions must be private (0700)"
          end
        end

        def load
          ensure_state_directory!
          directory = File.expand_path(@state_root)
          path = File.join(directory, PATH)
          return empty_journal if journal_directory_absent?(directory, path)
          verify_journal_directory!(directory)
          return empty_journal unless File.exist?(path) || File.symlink?(path)

          parse_journal(path)
        rescue JSON::ParserError => e
          emit("fix:journal_corrupt", error: e.message)
          raise "fix journal is corrupt: #{e.message}"
        end

        def empty_journal
          { "version" => VERSION, "runs" => [] }
        end

        def journal_directory_absent?(directory, path)
          return false if File.exist?(directory) || File.symlink?(directory)
          return true unless File.exist?(path) || File.symlink?(path)

          raise IOError, "fix journal exists without its state directory"
        end

        def verify_journal_directory!(directory)
          directory_stat = File.lstat(directory)
          unless directory_stat.directory? && !directory_stat.symlink?
            raise IOError, "refusing non-directory or symlinked journal state directory"
          end
          return unless (directory_stat.mode & 0o022).positive?

          raise IOError, "refusing group/world-writable journal state directory"
        end

        def parse_journal(path)
          path_stat = File.lstat(path)
          unless path_stat.file? && !path_stat.symlink? && path_stat.nlink == 1
            raise IOError, "refusing symlinked, hard-linked or non-regular fix journal"
          end
          raise IOError, "fix journal permissions must be private (0600 or stricter)" if (path_stat.mode & 0o077).positive?

          raw = JSON.parse(read_stable_journal(path))
          raise "fix journal version #{raw["version"]} is unsupported" unless raw["version"].to_i == VERSION
          runs = raw["runs"]
          raise "fix journal runs must be an array" unless runs.is_a?(Array)

          { "version" => VERSION, "runs" => runs }
        end

        def read_stable_journal(path)
          flags = File::RDONLY
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          content = File.open(path, flags) do |file|
            opened_stat = file.stat
            verify_journal_open_stat!(path, opened_stat)
            text = verify_journal_encoding!(file.read)
            verify_journal_after_stat!(path, opened_stat)
            text
          end
          content
        end

        def verify_journal_open_stat!(path, opened_stat)
          current_stat = File.lstat(path)
          unless current_stat.file? && !current_stat.symlink? &&
                 current_stat.nlink == 1 &&
                 current_stat.dev == opened_stat.dev && current_stat.ino == opened_stat.ino
            raise IOError, "fix journal path changed while opening"
          end
        end

        def verify_journal_encoding!(bytes)
          text = bytes.force_encoding(Encoding::UTF_8)
          raise EncodingError, "fix journal contains invalid UTF-8" unless text.valid_encoding?

          text
        end

        def verify_journal_after_stat!(path, opened_stat)
          after_stat = File.lstat(path)
          unless after_stat.file? && !after_stat.symlink? &&
                 after_stat.nlink == 1 &&
                 after_stat.dev == opened_stat.dev && after_stat.ino == opened_stat.ino &&
                 after_stat.size == opened_stat.size &&
                 after_stat.mtime == opened_stat.mtime && after_stat.ctime == opened_stat.ctime
            raise IOError, "fix journal changed while reading"
          end
        end

        # Callers hold the journal lock, so no writer is mid-persist while this runs.
        def persist(data, run_id: active_run_id(data))
          resolve_pending_marker!

          path = File.join(@state_root, PATH)
          ensure_state_directory!
          @lifecycle_observer.mutate(operation: "persist", item_count: Array(data["runs"]).size) do
            create_pending_marker!(run_id)
            write_atomic(path, JSON.pretty_generate(data) + "\n", mode: 0o600)
          end.tap do
            remove_pending_marker! if @pending_marker_owned
          end
        end

        def pending_marker_path = File.join(@state_root, PENDING_MARKER)

        def active_run_id(data)
          Array(data["runs"]).reverse.find { |run| run["state"] == "active" }&.fetch("id", nil)
        end

        # A marker left by a process that is gone is a write that process cannot
        # finish. The write is atomic, so once fix_runs.json parses the journal is
        # whole and the marker goes; a marker a live process holds, a symlink, or a
        # journal that does not parse stays refused for review.
        def resolve_pending_marker!
          marker = Master::Trace::MutationObserver::PendingMarker

          refusal = marker.resolve(pending_marker_path, label: state_relative(pending_marker_path)) do
            load
            "#{PATH} parses"
          end

          raise "#{MARKER_INCOMPLETE}: #{refusal}" if refusal
        end

        def create_pending_marker!(run_id)
          marker = Master::Trace::MutationObserver::PendingMarker
          marker.write!(pending_marker_path, operation: "persist", subject: run_id)
          @pending_marker_owned = true
        end

        def remove_pending_marker!
          path = pending_marker_path
          File.delete(path) if File.exist?(path) || File.symlink?(path)
          @pending_marker_owned = false
          true
        end

        def with_lock
          directory = File.expand_path(@state_root)
          lock_path = File.join(directory, LOCK)
          ensure_state_directory!
          verify_lock_directory!(directory)
          raise IOError, "refusing symlinked journal lock" if File.symlink?(lock_path)

          flags = File::RDWR | File::CREAT
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          File.open(lock_path, flags, 0o600) do |io|
            opened_stat = io.stat
            verify_lock_file!(lock_path, opened_stat)
            raise IOError, "could not acquire journal lock" unless io.flock(File::LOCK_EX)

            hold_journal_lock(lock_path, io, opened_stat) { yield }
          end
        end

        def verify_lock_directory!(directory)
          directory_stat = File.lstat(directory)
          unless directory_stat.directory? && !directory_stat.symlink?
            raise IOError, "refusing non-directory or symlinked journal state path"
          end
          return unless (directory_stat.mode & 0o022).positive?

          raise IOError, "refusing group/world-writable journal state directory"
        end

        def verify_lock_file!(lock_path, opened_stat)
          raise IOError, "journal lock is not a regular file" unless opened_stat.file?
          raise IOError, "journal lock permissions must be private (0600 or stricter)" unless
            (opened_stat.mode & 0o077).zero?

          current_stat = File.lstat(lock_path)
          return if current_stat.file? && !current_stat.symlink? &&
                    current_stat.dev == opened_stat.dev && current_stat.ino == opened_stat.ino

          raise IOError, "journal lock path changed while opening"
        end

        def hold_journal_lock(lock_path, io, opened_stat)
          current_stat = File.lstat(lock_path)
          unless current_stat.file? && !current_stat.symlink? &&
                 current_stat.dev == opened_stat.dev && current_stat.ino == opened_stat.ino
            raise IOError, "journal lock path changed while waiting for its lock"
          end
          migrate_legacy_state!
          yield
        ensure
          io.flock(File::LOCK_UN)
        end
      end
    end
  end
end
