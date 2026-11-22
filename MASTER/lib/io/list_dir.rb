# frozen_string_literal: true

module Master
  module Io
    class ListDir
      TIER = :safe
      NAME = "list_dir".freeze
      DESCRIPTION = "List directory contents, depth-limited.".freeze
      MAX_DEPTH = 5
      # The earlier 2,000-entry ceiling cut off the MASTER inventory before a
      # broad audit could even enumerate its files (the operator's tree had
      # 2,986 files). Keep the walk bounded, but above the normal source-tree size.
      MAX_ENTRIES = 10_000

      def initialize(root:, event_bus: nil)
        @root = File.realpath(root)
        @bus = event_bus
      end

      def call(path: ".", depth: 2, pattern: nil)
        resolved = resolve(path)
        return resolved if resolved.err?

        full = resolved.value!
        depth = depth.to_i.clamp(0, MAX_DEPTH)
        state = {
          seen: 0, files: 0, directories: 0, truncated: false,
          depth_limited: false, hidden_entries_excluded: 0, symlinks_skipped: 0
        }
        lines = list_tree(dir: full, depth:, pattern:, state:)
        lines << "... (max entries reached)" if state[:truncated]
        complete = !state[:truncated] && !state[:depth_limited]
        lines << "[tree receipt: path=#{path.to_s.inspect} entries=#{state[:seen]} files=#{state[:files]} " \
                  "directories=#{state[:directories]} depth=#{depth} complete=#{complete} " \
                  "depth_limited=#{state[:depth_limited]} truncated=#{state[:truncated]} " \
                  "hidden=excluded hidden_entries=#{state[:hidden_entries_excluded]} " \
                  "symlinks_skipped=#{state[:symlinks_skipped]}]"
        Result.ok(lines.join("\n"))
      end

      private

      def list_tree(dir:, depth:, pattern:, state:, indent: 0)
        return [] if depth < 0 || state[:truncated]

        all_entries = Dir.entries(dir).reject { |entry| %w[. ..].include?(entry) }
        visible_entries = all_entries.reject { |entry| entry.start_with?(".") }
        state[:hidden_entries_excluded] += all_entries.size - visible_entries.size
        entries = visible_entries.sort_by do |entry|
          path = File.join(dir, entry)
          [File.directory?(path) && !File.symlink?(path) ? 0 : 1, entry]
        end

        entries.flat_map do |entry|
          next [] if pattern && !File.fnmatch?(pattern, entry)
          if state[:seen] >= MAX_ENTRIES
            state[:truncated] = true
            break []
          end

          full = File.join(dir, entry)
          prefix = "  " * indent
          # Never follow a symlink while walking. A link can point outside
          # the workspace or back to an ancestor and must not expand the
          # inventory's authority or create a traversal loop.
          if File.symlink?(full)
            state[:symlinks_skipped] += 1
            next []
          end

          state[:seen] += 1
          if File.directory?(full)
            state[:directories] += 1
            if depth <= 0
              state[:depth_limited] = true
              ["#{prefix}#{entry}/"]
            else
              ["#{prefix}#{entry}/"] +
                list_tree(dir: full, depth: depth - 1, pattern:, state:, indent: indent + 1)
            end
          else
            state[:files] += 1
            ["#{prefix}#{entry}"]
          end
        end
      end

      def resolve(path)
        full = File.expand_path(path, @root)
        return Result.err("path escapes project root: #{path}", category: :validation) unless PathGuard.inside_real_root?(full, @root)
        return Result.err("not a directory: #{path}", category: :validation) unless File.directory?(full)
        Result.ok(full)
      end
    end
  end
end
