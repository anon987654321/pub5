# frozen_string_literal: true

# The inter-process /fix execution lock: flock custody plus the directory and
# lock-file safety checks every acquisition re-runs.
module Master
  module Fix
    class Kernel
      # Serializes /fix across independent Kernel instances and OS processes.
      # The per-instance mutex prevents local re-entry; flock is the authority
      # shared by every process operating on the same repository checkout.
      class ExecutionLock
        RELATIVE_PATH = ".master/fix-execution.lock"

        attr_reader :path

        def initialize(root:, state_root: nil)
          workspace = File.expand_path(root)
          @state_root = File.expand_path(state_root || MasterPaths.fix_state(root: workspace))
          @directory = @state_root
          @path = File.join(@state_root, File.basename(RELATIVE_PATH))
          @mutex = Mutex.new
        end

        def synchronize
          @mutex.synchronize do
            directory_stat = assert_lockable_directory!
            File.open(@path, lock_open_flags, 0o600) do |file|
              validate_lock_identity!(file, directory_stat)
              assert_private_lock_mode!(file, "execution lock permissions must be private (0600 or stricter)")
              raise IOError, "could not acquire /fix execution lock" unless file.flock(File::LOCK_EX)

              begin
                # A path or parent directory can be swapped while this process
                # waits for flock. Never enter /fix on an orphaned inode that no
                # longer serializes callers using the canonical lock pathname.
                validate_lock_identity!(file, directory_stat)
                assert_private_lock_mode!(file, "execution lock permissions changed while waiting")
                refuse_world_writable_directory!
                yield
              ensure
                file.flock(File::LOCK_UN)
              end
            end
          end
        end
        private

        # The checks every acquisition re-runs before the lock file is opened:
        # the state directory exists (created if needed) and is a private real
        # directory, and the lock path is not a symlink. Returns the directory
        # stat the identity checks compare against.
        def assert_lockable_directory!
          ensure_state_directory!
          directory_stat = File.lstat(@directory)
          unless directory_stat.directory? && !directory_stat.symlink?
            raise IOError, "refusing non-directory or symlinked .master path"
          end
          if (directory_stat.mode & 0o022).positive?
            raise IOError, "refusing group/world-writable .master directory"
          end
          raise IOError, "refusing symlinked execution lock" if File.symlink?(@path)

          directory_stat
        end

        def lock_open_flags
          flags = File::RDWR | File::CREAT
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          flags
        end

        def assert_private_lock_mode!(file, message)
          mode = file.stat.mode & 0o777
          raise IOError, message unless (mode & 0o077).zero?
        end

        def refuse_world_writable_directory!
          current_directory = File.lstat(@directory)
          if (current_directory.mode & 0o022).positive?
            raise IOError, "refusing group/world-writable .master directory"
          end
        end

        def ensure_state_directory!
          missing, cursor = missing_state_ancestors
          parent_stat = File.lstat(cursor)
          raise IOError, "refusing symlinked or non-directory fix state parent" unless parent_stat.directory? && !parent_stat.symlink?

          missing.each { |directory| create_private_state_directory!(directory) }
          assert_private_state_root!
        rescue SystemCallError => error
          raise IOError, "cannot prepare fix state directory: #{error.class}: #{error.message}"
        end

        # Walk up from the state directory to its nearest existing ancestor,
        # collecting every directory that does not exist yet, shallowest first.
        def missing_state_ancestors
          missing = []
          cursor = @directory
          until File.exist?(cursor) || File.symlink?(cursor)
            missing.unshift(cursor)
            parent = File.dirname(cursor)
            raise IOError, "fix state has no existing parent directory" if parent == cursor

            cursor = parent
          end
          [missing, cursor]
        end

        def create_private_state_directory!(directory)
          Dir.mkdir(directory, 0o700)
          stat = File.lstat(directory)
          raise IOError, "new fix state directory is not private" unless
            stat.directory? && !stat.symlink? && (stat.mode & 0o077).zero?
        end

        def assert_private_state_root!
          stat = File.lstat(@directory)
          unless stat.directory? && !stat.symlink? && (stat.mode & 0o022).zero?
            raise IOError, "refusing unsafe fix state directory"
          end
          if (stat.mode & 0o077).positive?
            raise IOError, "fix state directory permissions must be private"
          end
        end

        def validate_lock_identity!(file, original_directory_stat)
          current_directory = File.lstat(@directory)
          unless current_directory.directory? && !current_directory.symlink? &&
                 current_directory.dev == original_directory_stat.dev &&
                 current_directory.ino == original_directory_stat.ino
            raise IOError, "refusing changed .master directory during execution-lock acquisition"
          end

          opened = file.stat
          unless opened.file? && opened.nlink == 1
            raise IOError, "execution lock must be a singly linked regular file"
          end
          current = File.lstat(@path)
          unless current.file? && !current.symlink? &&
                 current.dev == opened.dev && current.ino == opened.ino
            raise IOError, "execution lock path changed while opening or waiting"
          end
        rescue SystemCallError => e
          raise IOError, "execution lock path changed while opening or waiting: #{e.message}"
        end

      end
    end
  end
end
