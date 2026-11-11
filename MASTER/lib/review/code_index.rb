# frozen_string_literal: true

require "digest"
require "prism"
require "set"
require "monitor"
require_relative "code_index/brief"

module Master
  module Review
    # Prism-parsed symbol graph; rebuilt on write events.
    class CodeIndex
      # Read-only query surface over the built symbol/reference graph —
      # separated from CodeIndex's own build/reindex lifecycle.
      module QueryApi
        def size
          @lock.synchronize { @symbols.size }
        end

        def symbols_in(file)
          with_built_index do
            full = File.expand_path(file, @root)
            @symbols.values.select { |s| s.file == full }
          end
        end

        def find(name)
          with_built_index { find_locked(name) }
        end

        def impact(fqn)
          with_built_index do
            refs = references_for(fqn)
            files = refs.map(&:from_file).uniq.map { |f| relativize(f) }
            callers = refs.map { |r| "#{relativize(r.from_file)}:#{r.from_line}" }.uniq
            { fqn:, reference_count: refs.size, files:, callers: }
          end
        end

        def query(name)
          with_built_index do
            hits = find_locked(name)
            next { error: "not found: #{name}" } if hits.empty?
            hits.map { |s| query_entry(s) }
          end
        end

        # Returns [file, line] for the first symbol matching name, or nil.
        def lookup(name)
          with_built_index do
            hit = find_locked(name).first
            hit ? [relativize(hit.file), hit.line] : nil
          end
        end
      end

      include QueryApi
      include Brief

      Symbol = Struct.new(:fqn, :type, :file, :line, :parent, :includes, keyword_init: true)
      Reference = Struct.new(:from_file, :from_line, :to_fqn, :ref_type, keyword_init: true)

      attr_reader :symbols, :references, :built_at

      def initialize(root:, event_bus: nil, persist: false)
        @root = File.expand_path(root)
        @store = persist ? CodeIndexStore.new(root: @root) : nil
        @bus = event_bus
        @symbols = {}
        @references = []
        @mtimes = {}
        @built_at = nil
        @errors = []
        @partial = false
        @lock = Monitor.new
        @build_thread = nil
      end

      def build(path: nil)
        @lock.synchronize do
          target = path ? File.expand_path(path, @root) : @root
          unless target == @root || target.start_with?(@root + File::SEPARATOR)
            raise ArgumentError, "code index scope escapes repository root"
          end

          @partial = !path.nil?
          files = Dir.glob(File.join(target, "**", "*.rb")).reject { |f| f.include?("/vendor/") }
          restored = path.nil? && @built_at.nil? && restore_snapshot
          if @built_at.nil? && !restored
            first_build(files)
          else
            # A scoped scan owns only paths below its target. Keep symbols and
            # prior errors outside that scope; they remain useful but make the
            # overall graph explicitly partial until a full scan reconciles it.
            @errors.reject! { |entry| path_within_scope?(File.expand_path(entry[:path], @root), target) }
            incremental_build(files, scope: target)
          end
          save_snapshot if @store && path.nil? && @errors.empty?
          @built_at = Time.now
          @orientation = nil
          @bus&.publish("code_index:built", files: files.size, symbols: @symbols.size,
                       complete: @errors.empty? && !@partial, partial: @partial, error_count: @errors.size)
        end
        self
      rescue StandardError => e
        @lock.synchronize do
          record_error(path || @root, :build, "#{e.class}: #{e.message}")
          @orientation = nil
        end
        @bus&.publish("code_index:error", error: e.message)
        self
      end

      def build_async
        @lock.synchronize do
          return self if @build_thread&.alive?

          @build_thread = Thread.new { build }
        end
        self
      end

      def ready?
        !@built_at.nil?
      end

      def wait_for_build
        @build_thread&.join
      end

      def built?
        !@built_at.nil?
      end

      # A usable graph and a fully analyzed graph are different claims. Parse
      # or read failures stay visible instead of looking like an empty index.
      def complete?
        @lock.synchronize { !@built_at.nil? && @errors.empty? && !@partial }
      end

      def partial?
        @lock.synchronize { @partial }
      end

      def errors
        @lock.synchronize { @errors.map(&:dup) }
      end

      def reindex(file)
        @lock.synchronize do
          full = File.expand_path(file, @root)
          purge_file(full)
          return unless File.file?(full)

          index_file(full)
          @orientation = nil
        end
      rescue StandardError => e
        @bus&.publish("code_index:reindex_error", path: file, error: e.message)
      end

      private

      def with_built_index(&blk)
        wait_for_build unless ready?
        @lock.synchronize(&blk)
      end

      def first_build(files)
        @symbols.clear
        @references.clear
        @mtimes.clear
        @errors.clear
        files.each do |f|
          index_file(f)
        end
      end

      def incremental_build(files, scope: @root)
        tracked_scope = @mtimes.keys.select { |file| path_within_scope?(file, scope) }
        tracked_scope.reject { |file| files.include?(file) }.each { |gone| purge_file(gone) }
        @errors.reject! do |entry|
          full = File.expand_path(entry[:path], @root)
          path_within_scope?(full, scope) && !files.include?(full)
        end
        changed = files.count { |file| reindex_if_stale(file) }
        @bus&.publish("code_index:incremental", changed:, total: files.size, scope: relativize(scope)) if changed > 0
      end

      def path_within_scope?(file, scope)
        file == scope || file.start_with?(scope + File::SEPARATOR)
      end

      def reindex_if_stale(file)
        sig = CodeIndexStore.signature(file)
        unless sig
          purge_file(file)
          record_error(file, :stat, "source file could not be inspected")
          return true
        end
        return false if @mtimes[file] == sig

        purge_file(file)
        @mtimes[file] = sig if index_file(file)
        true
      end

      # Loads the last boot's graph so incremental_build re-parses only files
      # whose timestamp, size or content digest changed. True when restored.
      def restore_snapshot
        snapshot = @store&.load
        return false unless snapshot

        snapshot[:symbols].each { |sym| store_symbol(sym) }
        @references.concat(snapshot[:references])
        @mtimes.merge!(snapshot[:signatures])
        @snapshot_tree = snapshot[:tree_hash]
        true
      end

      def save_snapshot
        return if @snapshot_tree && @snapshot_tree == CodeIndexStore.tree_hash(@mtimes)

        saved = @store.save(symbols: @symbols.values, references: @references, signatures: @mtimes)
        @snapshot_tree = CodeIndexStore.tree_hash(@mtimes) if saved
        saved
      end

      def purge_file(full)
        @symbols.delete_if { |_, s| s.file == full }
        @references.reject! { |r| r.from_file == full }
        @mtimes.delete(full)
        relative = relativize(full)
        @errors.reject! { |entry| entry[:path] == relative }
        @orientation = nil
      end

      def references_for(fqn)
        tail = "##{fqn}"
        @references.select { |r| to = r.to_fqn; to == fqn || to.end_with?(tail) }
      end

      def relativize(file)
        file.sub("#{@root}/", "")
      end

      def find_locked(name)
        exact = @symbols.values.select { |symbol| symbol.fqn == name.to_s }
        return exact unless exact.empty?

        suffix = name.to_s
        @symbols.values.select { |symbol| symbol.fqn.include?(suffix) }
      end

      # Reopened Ruby classes/modules and methods may have more than one
      # definition. Keep the first FQN key for compatibility, then retain each
      # additional definition under a stable path-and-line key.
      def store_symbol(symbol)
        key = symbol.fqn
        if @symbols.key?(key)
          base = "#{key}@#{relativize(symbol.file)}:#{symbol.line}"
          key = base
          duplicate = 2
          while @symbols.key?(key)
            key = "#{base}:#{duplicate}"
            duplicate += 1
          end
        end
        @symbols[key] = symbol
      end

      def format_summary_entry(sym)
        parent_name = sym.parent
        parent = parent_name && parent_name != "Object" ? " < #{parent_name}" : ""
        "  #{sym.fqn}#{parent} (#{relativize(sym.file)}:#{sym.line})"
      end

      def query_entry(sym)
        refs = references_for(sym.fqn)
        {
          fqn: sym.fqn,
          type: sym.type,
          file: relativize(sym.file),
          line: sym.line,
          parent: sym.parent,
          used_in: refs.first(10).map { |r| "#{relativize(r.from_file)}:#{r.from_line}" },
        }
      end

      def index_file(file)
        src, signature = CodeIndexStore.read_source(file, root: @root)
        parse_result = Prism.parse(src)
        unless parse_result.success?
          detail = parse_result.errors.first(5).map { |error| error.message.to_s }.join("; ")
          record_error(file, :parse, detail.empty? ? "Prism parse failed" : detail)
          @bus&.publish("code_index:parse_error", path: file, error: detail)
          return false
        end

        visitor = SymbolVisitor.new(file:, root: @root)
        parse_result.value.accept(visitor)
        unless CodeIndexStore.signature(file) == signature
          record_error(file, :changed, "source changed while Prism analyzed it; retry the index build")
          @bus&.publish("code_index:parse_error", path: file, error: "source changed during analysis")
          return false
        end

        visitor.symbols.each { |symbol| store_symbol(symbol) }
        @references.concat(visitor.references)
        @mtimes[file] = signature
        true
      rescue StandardError => e
        record_error(file, :read, "#{e.class}: #{e.message}")
        @bus&.publish("code_index:parse_error", path: file, error: e.message)
        false
      end

      def record_error(file, kind, message)
        relative = relativize(File.expand_path(file, @root))
        @errors.reject! { |entry| entry[:path] == relative }
        @errors << {
          path: relative,
          kind: kind.to_sym,
          message: message.to_s.slice(0, 240),
        }.freeze
      end
    end
  end
end
