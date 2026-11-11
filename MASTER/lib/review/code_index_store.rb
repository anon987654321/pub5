# frozen_string_literal: true

require "digest"
require "json"
require "prism"
require_relative "../io/atomic_write"

module Master
  module Review
    # Keeps CodeIndex's symbol graph between boots under .master/code_index/.
    #
    # The file records per-source nanosecond mtime, size and content digest,
    # so same-size edits with preserved timestamps cannot leave a stale graph.
        # Its name comes from the workspace root, not from the tree hash: a name
    # keyed by the tree hash
    # changes on every edit and leaves nothing to rebuild incrementally from. The
    # tree hash rides inside the file, so an untouched tree is known without
    # comparing a single row. A stamp of the schema, Prism's version and the
    # parser's own source rejects a snapshot made by different parsing logic.
    class CodeIndexStore
      include Master::Io::AtomicWrite

      SCHEMA = 2
      REL_DIR = File.join(".master", "code_index").freeze
      MAX_SNAPSHOT_BYTES = 128 * 1024 * 1024

      def initialize(root:)
        @root = root
        @path = File.join(root, REL_DIR, "#{Digest::SHA256.hexdigest(root)[0, 16]}.json")
      end

      attr_reader :path

      def self.signature(file)
        read_source(file).last
      rescue SystemCallError, IOError
        nil
      end

      # Read and fingerprint the same open file descriptor. A path may be
      # replaced between a separate File.read and SHA calculation; signatures
      # must describe the bytes Prism actually parsed, not a later pathname.
      def self.read_source(file, root: nil)
        full = File.expand_path(file)
        root_real = File.realpath(root) if root
        before = File.lstat(full)
        raise IOError, "code index source is not a regular non-symlink file" unless before.file? && !before.symlink?

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(full, flags) do |io|
          opened = io.stat
          current = File.lstat(full)
          unless same_file?(before, opened) && same_file?(current, opened)
            raise IOError, "code index source path changed while opening"
          end
          resolved = File.realpath(full)
          if root_real && !inside_root?(resolved, root_real)
            raise IOError, "code index source escapes its repository"
          end

          raw = io.read
          after = io.stat
          current = File.lstat(full)
          unless stable_file?(opened, after) && same_file?(current, after)
            raise IOError, "code index source changed while reading"
          end
          resolved_after = File.realpath(full)
          if root_real && !inside_root?(resolved_after, root_real)
            raise IOError, "code index source moved outside its repository"
          end

          source = raw.dup.force_encoding(Encoding::UTF_8)
          signature = [(opened.mtime.to_r * 1_000_000_000).to_i, opened.size, Digest::SHA256.hexdigest(raw)]
          [source, signature]
        end
      rescue SystemCallError => error
        raise IOError, "cannot safely read code index source: #{error.class}: #{error.message}"
      end

      def self.same_file?(left, right)
        left.file? && !left.symlink? && right.file? &&
          left.dev == right.dev && left.ino == right.ino && left.nlink == right.nlink
      end
      private_class_method :same_file?

      def self.stable_file?(before, after)
        same_file?(before, after) && before.size == after.size &&
          before.mtime == after.mtime && before.ctime == after.ctime
      end
      private_class_method :stable_file?

      def self.inside_root?(path, root)
        path == root || path.start_with?(root + File::SEPARATOR)
      end
      private_class_method :inside_root?

      def self.tree_hash(signatures)
        # A file that vanished between the glob and its stat has a nil signature.
        Digest::SHA256.hexdigest(signatures.sort.map { |file, sig| "#{file}\0#{Array(sig).join(':')}" }.join("\n"))
      end

      # { symbols:, references:, signatures:, tree_hash: } or nil when absent or stale.
      def load
        raw = read_snapshot
        return unless raw

        data = JSON.parse(raw)
        return unless valid_snapshot?(data)

        files = data["files"]
        {
          symbols: data["symbols"].map { |row| symbol(row, files) },
          references: data["references"].map { |row| reference(row, files) },
          signatures: data["signatures"],
          tree_hash: data["tree_hash"],
        }
      rescue StandardError
        # The cache is derived data. Invalid shape, parser drift, permission
        # trouble or concurrent replacement means a cold rebuild, never a
        # repository-wide analysis failure.
        nil
      end

      def save(symbols:, references:, signatures:)
        # Files repeat on every row, so rows carry an index into one table.
        files = signatures.keys
        index = files.each_with_index.to_h
        body = {
          stamp:, root: @root, tree_hash: self.class.tree_hash(signatures), signatures:, files:,
          symbols: symbols.map { |s| [s.fqn, s.type, index.fetch(s.file), s.line, s.parent, s.includes] },
          references: references.map { |r| [index.fetch(r.from_file), r.from_line, r.to_fqn, r.ref_type] }
        }
        write_atomic(@path, JSON.generate(body), mode: 0o600)
        true
      rescue SystemCallError, IOError
        nil
      end

      private

      def valid_snapshot?(data)
        return false unless data.is_a?(Hash)
        return false unless data["stamp"] == stamp && data["root"] == @root
        return false unless data["files"].is_a?(Array) &&
                            data["files"].all? { |file| file.is_a?(String) && !file.empty? } &&
                            data["files"].uniq == data["files"]
        return false unless data["signatures"].is_a?(Hash) &&
                            data["signatures"].keys == data["files"]
        return false unless data["signatures"].all? do |_file, signature|
          signature.is_a?(Array) && signature.size == 3 &&
            signature[0].is_a?(Integer) && signature[1].is_a?(Integer) && signature[1] >= 0 &&
            signature[2].is_a?(String) && signature[2].match?(/\\A[0-9a-f]{64}\\z/)
        end
        return false unless data["tree_hash"].is_a?(String) &&
                            data["tree_hash"].match?(/\\A[0-9a-f]{64}\\z/) &&
                            self.class.tree_hash(data["signatures"]) == data["tree_hash"]
        return false unless data["symbols"].is_a?(Array) && data["references"].is_a?(Array)

        data["symbols"].all? do |row|
          row.is_a?(Array) && row.size == 6 &&
            row[0].is_a?(String) && !row[0].empty? &&
            row[1].is_a?(String) && %w[class module constant method].include?(row[1]) &&
            row[2].is_a?(Integer) && row[2].between?(0, data["files"].size - 1) &&
            row[3].is_a?(Integer) && row[3].positive? &&
            (row[4].nil? || row[4].is_a?(String)) &&
            row[5].is_a?(Array) && row[5].all? { |item| item.is_a?(String) }
        end && data["references"].all? do |row|
          row.is_a?(Array) && row.size == 4 &&
            row[0].is_a?(Integer) && row[0].between?(0, data["files"].size - 1) &&
            row[1].is_a?(Integer) && row[1].positive? &&
            row[2].is_a?(String) && !row[2].empty? &&
            row[3].is_a?(String) && !row[3].empty?
        end
      end

      # Open the cache without following a last-moment symlink replacement,
      # bound the allocation, and verify the opened inode and parent directory
      # both before and after reading. A cache is disposable; unsafe means miss.
      def read_snapshot
        directory = File.dirname(@path)
        directory_stat = File.lstat(directory)
        return unless directory_stat.directory? && !directory_stat.symlink? &&
                      verified_atomic_directory(directory) == directory

        before = File.lstat(@path)
        return unless before.file? && !before.symlink? && before.nlink == 1

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(@path, flags) do |file|
          opened = file.stat
          current = File.lstat(@path)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == opened.dev && current.ino == opened.ino &&
                 opened.dev == before.dev && opened.ino == before.ino
            raise IOError, "code index snapshot path changed while opening"
          end
          raw = file.read(MAX_SNAPSHOT_BYTES + 1)
          raise IOError, "code index snapshot exceeds the 128 MiB safety limit" if raw.bytesize > MAX_SNAPSHOT_BYTES

          after = file.stat
          current = File.lstat(@path)
          parent = File.lstat(directory)
          unless current.file? && !current.symlink? && current.nlink == 1 &&
                 current.dev == after.dev && current.ino == after.ino &&
                 after.dev == opened.dev && after.ino == opened.ino &&
                 after.size == opened.size && after.mtime == opened.mtime &&
                 after.ctime == opened.ctime && raw.bytesize == after.size &&
                 parent.directory? && !parent.symlink? &&
                 parent.dev == directory_stat.dev && parent.ino == directory_stat.ino &&
                 verified_atomic_directory(directory) == directory
            raise IOError, "code index snapshot changed while reading"
          end
          raw
        end
      rescue Errno::ENOENT
        nil
      end

      def stamp
        @stamp ||= [SCHEMA, Prism::VERSION, parser_digest]
      end

      def parser_digest
        sources = [File.join(__dir__, "code_index.rb"), File.join(__dir__, "code_index", "symbol_visitor.rb")]
        Digest::SHA256.hexdigest(sources.map { |file| File.read(file) }.join)[0, 16]
      end

      def symbol(row, files)
        CodeIndex::Symbol.new(fqn: row[0], type: row[1].to_sym, file: files[row[2]], line: row[3], parent: row[4], includes: row[5])
      end

      def reference(row, files)
        CodeIndex::Reference.new(from_file: files[row[0]], from_line: row[1], to_fqn: row[2], ref_type: row[3].to_sym)
      end
    end
  end
end
