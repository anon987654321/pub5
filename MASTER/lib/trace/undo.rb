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
        directory_stat = secure_journal_directory(directory)

        lock_path = "#{@journal}#{LOCK_SUFFIX}"
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW, false)
        File.open(lock_path, flags, 0o600) do |lock|
          assert_stable_lock!(lock, lock_path)
          lock.chmod(0o600)
          lock.flock(File::LOCK_EX)
          changed = !same_directory?(directory, directory_stat)
          raise IOError, "undo journal directory changed while locking" if changed

          yield
        end
      end

      # The journal contains full pre-write file contents, so others must never
      # reach its directory. A deliberate group hand-off is kept
      # (MasterPaths.private_dir_mode): on vm23 .master is dev:master for the
      # daemon, and a flat 0700 here locked the daemon out after every dev
      # boot, then raised EPERM in the daemon's own boot (2026-11-25). chmod is
      # the owner's alone; anyone else gets the check.
      def secure_journal_directory(directory)
        FileUtils.mkdir_p(directory, mode: 0o700)
        stat = File.lstat(directory)
        raise IOError, "undo journal directory is not a real directory" unless stat.directory? && !stat.symlink?

        expected = MasterPaths.private_dir_mode(directory)
        File.chmod(expected, directory) if (stat.mode & 0o7777) != expected && File.owned?(directory)
        secured = same_directory?(directory, stat) && (File.lstat(directory).mode & 0o007).zero?
        raise IOError, "undo journal directory could not be secured" unless secured

        stat
      end

      def same_directory?(directory, stat)
        current = File.lstat(directory)
        current.directory? && !current.symlink? && current.dev == stat.dev && current.ino == stat.ino
      end

      def assert_stable_lock!(lock, lock_path)
        lock_stat = File.lstat(lock_path)
        opened = lock.stat
        stable = lock_stat.file? && !lock_stat.symlink? && lock_stat.dev == opened.dev && lock_stat.ino == opened.ino
        raise IOError, "undo journal lock is not a stable regular file" unless stable
      end

      def delete_tmp_file(path)
        File.delete(path) if path && File.exist?(path)
      rescue StandardError => e
        @bus&.publish("undo:tmp_delete_error", error: e.message, path:)
      end
    end
  end
end
