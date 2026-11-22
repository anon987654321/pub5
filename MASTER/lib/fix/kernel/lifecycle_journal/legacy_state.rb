# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # One-time migration of the old checkout-local /fix state into the
      # persistent state root: lock acquisition, live-run refusal and
      # copy-verified import, with the old files left as a rollback source.
      class LifecycleJournal
        LEGACY_FILES = %w[
          fix_runs.json .fix_runs.pending log.jsonl mission.json costs.jsonl
        ].freeze
        LEGACY_GLOBS = %w[mission-*.json fix-*.log triangle-*.log].freeze
        LEGACY_DIRECTORIES = %w[
          fix_assessments fix_architecture checkpoints fix_transcripts
        ].freeze
        LEGACY_LOCKS = %w[
          fix-execution.lock fix_runs.lock mission.lock
        ].freeze

        private

        # One-time, copy-verified import from the old checkout-local state.
        # The old files remain untouched as a rollback source. A live old lock
        # or an unexpired mission is a hard stop: two state roots must never
        # become concurrent writers for the same repository.
        def migrate_legacy_state!
          return if @migration_complete

          return accept_existing_migration_receipt! if migration_receipt_present?

          import_legacy_state!
        rescue JSON::ParserError => error
          raise IOError, "persistent /fix migration receipt is corrupt: #{error.message}"
        end

        def migration_receipt_present?
          marker_path = File.join(@state_root, MIGRATION_MARKER)
          File.exist?(marker_path) || File.symlink?(marker_path)
        end

        def accept_existing_migration_receipt!
          marker_path = File.join(@state_root, MIGRATION_MARKER)
          raise IOError, "refusing symlinked /fix migration receipt" if File.symlink?(marker_path)

          receipt_stat = File.lstat(marker_path)
          unless receipt_stat.file? && receipt_stat.nlink == 1 && (receipt_stat.mode & 0o077).zero?
            raise IOError, "unsafe /fix migration receipt"
          end
          JSON.parse(File.read(marker_path, encoding: "UTF-8"))
          @migration_complete = true
          true
        end

        def import_legacy_state!
          legacy = @legacy_state_roots.reject { |directory| File.expand_path(directory) == @state_root }
          locked = []
          copied = []
          begin
            legacy.each { |directory| import_legacy_root!(directory, locked, copied) }
            write_migration_receipt!(legacy, copied)
          ensure
            locked.reverse_each do |io|
              io.flock(File::LOCK_UN)
              io.close
            rescue IOError, SystemCallError
              nil
            end
          end
        end

        def import_legacy_root!(directory, locked, copied)
          return unless File.exist?(directory) || File.symlink?(directory)

          raise IOError, "refusing symlinked legacy /fix state directory: #{directory}" if File.symlink?(directory)
          stat = File.lstat(directory)
          unless stat.directory? && (stat.mode & 0o022).zero?
            raise IOError, "unsafe legacy /fix state directory: #{directory}"
          end
          locked.concat(lock_legacy_state!(directory))
          refuse_live_legacy_runs!(directory)
          copied.concat(copy_legacy_state!(directory))
        end

        def write_migration_receipt!(legacy, copied)
          receipt = {
            "schema_version" => 1,
            "status" => "verified",
            "repository_state" => File.basename(File.dirname(@state_root)),
            "sources" => legacy.select { |directory| File.directory?(directory) },
            "copied" => copied.sort_by { |row| [row.fetch("source"), row.fetch("path")] },
            "created_at" => Time.now.utc.iso8601,
          }
          write_atomic(File.join(@state_root, MIGRATION_MARKER), JSON.pretty_generate(receipt) + "\n", mode: 0o600)
          @migration_complete = true
          emit("fix:legacy_state_imported", roots: receipt["sources"].size,
               files: receipt["copied"].size, state_root: @state_root)
          true
        end

        def lock_legacy_state!(directory)
          paths = LEGACY_LOCKS.map { |name| File.join(directory, name) }
          paths.concat(Dir.glob(File.join(directory, "mission-*.lock")).sort)
          paths.uniq.filter_map { |path| lock_legacy_lock!(path) }
        rescue SystemCallError => error
          raise IOError, "cannot safely inspect legacy /fix locks: #{error.class}: #{error.message}"
        end

        def lock_legacy_lock!(path)
          return unless File.exist?(path) || File.symlink?(path)
          raise IOError, "refusing symlinked legacy /fix lock: #{path}" if File.symlink?(path)

          flags = File::RDWR
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          io = File.open(path, flags)
          stat = io.stat
          unless stat.file? && stat.nlink == 1
            io.close
            raise IOError, "legacy /fix lock is not a singly linked file: #{path}"
          end
          return io if io.flock(File::LOCK_EX | File::LOCK_NB)

          io.close
          raise IOError, "legacy /fix process still owns #{File.basename(path)}; refusing state cutover"
        end

        def refuse_live_legacy_runs!(directory)
          refuse_live_legacy_journal!(directory)
          refuse_live_legacy_missions!(directory)
        rescue JSON::ParserError => error
          raise IOError, "legacy /fix state is corrupt and cannot be migrated: #{error.message}"
        end

        def refuse_live_legacy_journal!(directory)
          journal = File.join(directory, "fix_runs.json")
          return unless File.file?(journal) && !File.symlink?(journal)

          data = JSON.parse(File.read(journal, encoding: "UTF-8"))
          Array(data["runs"]).each do |run|
            next unless run["state"].to_s == "active"
            next unless process_alive?(run["pid"])

            raise IOError, "legacy /fix run #{run["id"]} is still active; refusing state cutover"
          end
        end

        def refuse_live_legacy_missions!(directory)
          mission_paths = [File.join(directory, "mission.json")] + Dir.glob(File.join(directory, "mission-*.json"))
          mission_paths.each do |path|
            next unless File.file?(path) && !File.symlink?(path)

            refuse_live_legacy_mission!(path)
          rescue ArgumentError
            raise IOError, "legacy /fix mission has an invalid lease; refusing state cutover"
          end
        end

        def refuse_live_legacy_mission!(path)
          record = JSON.parse(File.read(path, encoding: "UTF-8"))
          return unless %w[running waiting].include?(record["state"].to_s)
          return if Time.parse(record["lease_until"].to_s) <= Time.now.utc

          owner = record["lease_owner"].to_s
          pid = owner.split(":")[1].to_i if owner.start_with?("#{Socket.gethostname}:")
          return if pid && pid.positive? && !process_alive?(pid)

          raise IOError, "legacy /fix mission #{record["id"]} has an unexpired lease; refusing state cutover"
        end

        def copy_legacy_state!(directory)
          entries = []
          candidates = LEGACY_FILES.map { |name| File.join(directory, name) }
          LEGACY_GLOBS.each { |pattern| candidates.concat(Dir.glob(File.join(directory, pattern))) }
          LEGACY_DIRECTORIES.each { |name| candidates << File.join(directory, name) }
          candidates.uniq.sort.each do |source|
            next unless File.exist?(source) || File.symlink?(source)

            relative = source.delete_prefix(directory + File::SEPARATOR)
            destination = File.join(@state_root, relative)
            entries.concat(copy_legacy_entry!(source, destination, directory))
          end
          entries
        end

        def copy_legacy_entry!(source, destination, legacy_root)
          stat = File.lstat(source)
          raise IOError, "refusing symlink in legacy /fix state: #{source}" if stat.symlink?

          return copy_legacy_directory!(source, destination, legacy_root, stat) if stat.directory?

          copy_legacy_file!(source, destination, legacy_root, stat)
        rescue SystemCallError => error
          raise IOError, "cannot import legacy /fix artifact #{source}: #{error.class}: #{error.message}"
        end

        def copy_legacy_directory!(source, destination, legacy_root, stat)
          raise IOError, "unsafe legacy /fix directory permissions: #{source}" if (stat.mode & 0o022).positive?
          ensure_state_child_directory!(destination)
          rows = []
          Dir.children(source).sort.each do |name|
            child = File.join(source, name)
            target = File.join(destination, name)
            rows.concat(copy_legacy_entry!(child, target, legacy_root))
          end
          rows
        end

        def copy_legacy_file!(source, destination, legacy_root, stat)
          unless stat.file? && stat.nlink == 1
            raise IOError, "legacy /fix artifact must be a singly linked regular file: #{source}"
          end
          # Older fix-here logs inherited the process umask and may be 0644.
          # The destination is always private (0600 under a 0700 state root);
          # preserve evidence without carrying the source's broad mode forward.
          source_mode = format("%04o", stat.mode & 0o777)

          payload = read_legacy_state_file(source, stat)
          digest = Digest::SHA256.hexdigest(payload)
          ensure_state_child_directory!(File.dirname(destination))
          if File.exist?(destination) || File.symlink?(destination)
            verify_existing_legacy_artifact!(destination, digest)
          else
            write_atomic(destination, payload, mode: 0o600)
          end
          [legacy_copied_row(source, destination, legacy_root, digest, payload, source_mode)]
        end

        def verify_existing_legacy_artifact!(destination, digest)
          raise IOError, "refusing symlink at persistent /fix destination: #{destination}" if File.symlink?(destination)
          existing = File.lstat(destination)
          unless existing.file? && existing.nlink == 1 && (existing.mode & 0o077).zero?
            raise IOError, "unsafe existing persistent /fix artifact: #{destination}"
          end
          existing_digest = Digest::SHA256.file(destination).hexdigest
          return if existing_digest == digest

          raise IOError, "conflicting legacy /fix artifacts at #{destination}"
        end

        def legacy_copied_row(source, destination, legacy_root, digest, payload, source_mode)
          {
            "source" => source.delete_prefix(legacy_root + File::SEPARATOR),
            "path" => state_relative(destination),
            "sha256" => digest,
            "bytes" => payload.bytesize,
            "source_mode" => source_mode,
          }
        end

        def read_legacy_state_file(path, before)
          flags = File::RDONLY
          flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
          File.open(path, flags) do |io|
            opened = io.stat
            current = File.lstat(path)
            unless current.file? && !current.symlink? && current.nlink == 1 &&
                   current.dev == opened.dev && current.ino == opened.ino &&
                   opened.dev == before.dev && opened.ino == before.ino
              raise IOError, "legacy /fix artifact changed while opening: #{path}"
            end
            payload = io.read
            after = File.lstat(path)
            unless after.file? && !after.symlink? && after.nlink == 1 &&
                   after.dev == opened.dev && after.ino == opened.ino &&
                   after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
              raise IOError, "legacy /fix artifact changed while reading: #{path}"
            end
            payload
          end
        end

        def ensure_state_child_directory!(directory)
          root = File.expand_path(@state_root)
          target = File.expand_path(directory)
          unless target == root || target.start_with?(root + File::SEPARATOR)
            raise IOError, "persistent /fix path escapes state root: #{target}"
          end
          return root if target == root

          relative = target.delete_prefix(root + File::SEPARATOR)
          cursor = root
          relative.split(File::SEPARATOR).each do |component|
            cursor = File.join(cursor, component)
            raise IOError, "refusing symlink in persistent /fix state: #{cursor}" if File.symlink?(cursor)
            Dir.mkdir(cursor, 0o700) unless File.exist?(cursor)
            stat = File.lstat(cursor)
            unless stat.directory? && !stat.symlink? && (stat.mode & 0o077).zero?
              raise IOError, "persistent /fix directory must be private: #{cursor}"
            end
          end
          target
        rescue SystemCallError => error
          raise IOError, "cannot create persistent /fix directory: #{error.class}: #{error.message}"
        end
      end
    end
  end
end
