# frozen_string_literal: true

module Master
  module Fix
    class Kernel
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
        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        flags
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

      def revalidated_log_head(file, cached)
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
        flags = File::RDWR | File::CREAT | File::APPEND
        flags |= File::EXCL if exclusive
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
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
    end
  end
end
