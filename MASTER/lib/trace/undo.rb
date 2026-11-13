# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Trace
  # Persistent undo: snapshots file content before writes, restores on demand.
  # Journal survives restarts via .master/undo_journal.jsonl.
  #
  # File-level, not turn-level. The branch is shared, so a turn's commit need
  # not be HEAD by the time anyone asks, and resetting it drops what landed after;
  # `git revert` of a commit a person names is that move. Fold writes go through
  # Core::World#do_write, which journals nothing, so after a fold turn undo!
  # restores the newest tool-path snapshot, which may be an earlier session's.
    class Undo
      include ::Master::Io::AtomicWrite

      MAX_JOURNAL = 50
      LOCK_SUFFIX = ".lock".freeze

      def initialize(session:, event_bus: nil, root: Dir.pwd)
        @session = session
        @bus = event_bus
        @root = File.expand_path(root)
        @journal = File.join(@root, ".master", "undo_journal.jsonl")
        @stack = with_journal_lock { load_journal }
      end

      def snapshot(path)
        @bus&.publish("voice:catchphrase", phrase: "Backing up first.", path:)
        content = File.exist?(path) ? File.read(path) : nil
        @session.snapshot(path, content)
        with_journal_lock do
          # A second MASTER process may have written since this object was
          # initialized. Reload under the shared lock before appending.
          @stack = load_journal
          @stack << { "path" => path, "content" => content, "ts" => Time.now.to_i }
          @stack.shift while @stack.size > MAX_JOURNAL
          persist_journal
        end
        Result.ok(path)
      rescue StandardError => e
        Result.err("undo snapshot: #{e.message}", category: :unknown)
      end

      def undo!(steps: 1) = replay(@stack, "undo", steps)

      # The heartbeat uses the same lock and atomic writer as snapshot/undo.
      # Entries contain their snapshot bytes inline, so pruning has no external
      # blob files to reclaim or references to guess at.
      def prune!
        with_journal_lock do
          @stack = load_journal
          before = @stack.size
          @stack = @stack.last(MAX_JOURNAL)
          removed = before - @stack.size
          persist_journal if removed.positive?
          removed
        end
      end

      def history(limit: 10)
        entries = with_journal_lock { @stack = load_journal }
        entries.last(limit).reverse.map.with_index(1) do |entry, i|
          time = entry["ts"] ? Time.at(entry["ts"]).strftime("%H:%M:%S") : "?"
          "#{i}. #{entry["path"]} (#{time})"
        end
      end

      private

      # Pop the file's previous content off the stack and put it back.
      def replay(_from, verb, steps)
        with_journal_lock do
          @stack = load_journal
          return Result.err("nothing to #{verb}", category: :validation) if @stack.empty?

          paths = []
          [Integer(steps), @stack.size].min.times do
            entry = @stack.pop
            restore(entry["path"], entry["content"])
            paths << entry["path"]
            @bus&.publish("#{verb}:applied", path: paths.last)
          end

          persist_journal
          Result.ok(paths.size == 1 ? paths.first : paths)
        end
      rescue ArgumentError, TypeError => e
        Result.err("undo steps: #{e.message}", category: :validation)
      end

      def restore(path, content)
        if content.nil?
          File.delete(path) if File.exist?(path)
        else
          write_atomic(path, content)
        end
      rescue StandardError => e
        delete_tmp_file(tmp_path) if defined?(tmp_path)
        raise
      end

      def load_journal
        return [] unless File.exist?(@journal) || File.symlink?(@journal)

        stat = File.lstat(@journal)
        raise IOError, "undo journal is not a singly linked regular file" unless stat.file? && !stat.symlink? && stat.nlink == 1

        File.readlines(@journal).filter_map do |line|
          JSON.parse(line.strip)
        rescue JSON::ParserError => e
          Master::Ground::Swallow.log(e, context: "Undo.load_journal")
          nil
        end
      rescue StandardError => e
        @bus&.publish("undo:read_error", error: e.message) if defined?(@bus)
        raise if e.is_a?(IOError)

        []
      end

      # Owner-only: the journal holds the whole content of every file it snapshots, and
      # written 0644 it made a 0600 key or env file readable by anyone the source was not.
      def persist_journal
        write_atomic(@journal, @stack.map { |entry| "#{JSON.generate(entry)}\n" }.join, mode: 0o600)
      rescue StandardError => e
        delete_tmp_file(tmp_path) if defined?(tmp_path)
        raise
      end

      def with_journal_lock
        directory = File.dirname(@journal)
        FileUtils.mkdir_p(directory, mode: 0o700)
        directory_stat = File.lstat(directory)
        raise IOError, "undo journal directory is not a real directory" unless directory_stat.directory? && !directory_stat.symlink?

        # The journal contains full pre-write file contents. A pre-existing
        # permissive .master directory defeats the journal's 0600 file mode.
        unless (directory_stat.mode & 0o7777) == 0o700
          File.chmod(0o700, directory)
          secured = File.lstat(directory)
          unless secured.directory? && !secured.symlink? &&
                 secured.dev == directory_stat.dev && secured.ino == directory_stat.ino &&
                 (secured.mode & 0o7777) == 0o700
            raise IOError, "undo journal directory could not be secured"
          end
        end

        lock_path = "#{@journal}#{LOCK_SUFFIX}"
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW, false)
        File.open(lock_path, flags, 0o600) do |lock|
          lock_stat = File.lstat(lock_path)
          opened_stat = lock.stat
          unless lock_stat.file? && !lock_stat.symlink? &&
                 lock_stat.dev == opened_stat.dev && lock_stat.ino == opened_stat.ino
            raise IOError, "undo journal lock is not a stable regular file"
          end
          lock.chmod(0o600)
          lock.flock(File::LOCK_EX)

          current_directory = File.lstat(directory)
          unless current_directory.directory? && !current_directory.symlink? &&
                 current_directory.dev == directory_stat.dev && current_directory.ino == directory_stat.ino
            raise IOError, "undo journal directory changed while locking"
          end
          yield
        end
      end

      def delete_tmp_file(path)
        File.delete(path) if path && File.exist?(path)
      rescue StandardError => e
        @bus&.publish("undo:tmp_delete_error", error: e.message, path:)
      end
    end
  end
end
