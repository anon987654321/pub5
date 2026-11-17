# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # Inter-process exclusion, re-opening the class defined in
      # fix/mission.rb. Every mutation funnels through #with_lock: the lock
      # file is opened, identity-checked, flocked, re-checked after waiting,
      # and unlocked before the file closes, so a replaced or symlinked lock
      # can never guard a foreign writer. Keep the check/acquire/recheck
      # order exactly as written; mission leasing is concurrency-sensitive.
      private

      def with_lock
        prepare_shared_state!
        lock_path = self.class.send(:lock_file_path, root: @root, namespace: @namespace)
        FileUtils.mkdir_p(File.dirname(lock_path), mode: 0o700)
        raise IOError, "refusing symlinked mission lock" if File.symlink?(lock_path)

        File.open(lock_path, lock_open_flags, 0o600) do |io|
          opened = verify_lock_identity!(io, lock_path)
          raise IOError, "could not acquire mission lock" unless io.flock(File::LOCK_EX)
          begin
            verify_lock_unchanged!(opened, lock_path)
            yield
          ensure
            io.flock(File::LOCK_UN)
          end
        end
      end

      def lock_open_flags
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        flags
      end

      def verify_lock_identity!(io, lock_path)
        opened = io.stat
        current = File.lstat(lock_path)
        unless opened.file? && opened.nlink == 1 && !current.symlink? &&
               current.dev == opened.dev && current.ino == opened.ino &&
               (opened.mode & 0o077).zero?
          raise IOError, "mission lock must be a private, singly linked regular file"
        end
        opened
      end

      def verify_lock_unchanged!(opened, lock_path)
        current = File.lstat(lock_path)
        unless current.file? && !current.symlink? &&
               current.dev == opened.dev && current.ino == opened.ino
          raise IOError, "mission lock path changed while waiting"
        end
      end

      def prepare_shared_state!
        return true if @state_prepared

        require_relative "../kernel" unless defined?(Master::Fix::Kernel::LifecycleJournal)
        Master::Fix::Kernel.new(root: @root, actor: "mission-state")
          .lifecycle_journal.prepare_state!
        @state_prepared = true
      end
    end
  end
end
