# frozen_string_literal: true

require "fileutils"

module Master
  module Io
    class WriteFile
      include Base
      TIER = :guarded
      NAME = "write_file".freeze
      DESCRIPTION = "Atomically write content to a file, with undo snapshot and a current-turn read requirement for existing files.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil, ground_truth: nil)
        @root, @undo, @governor, @bus, @diff_stager, @ground_truth =
          File.realpath(root), undo, governor, event_bus, diff_stager, ground_truth
      end

      # A whole-file write replaces whatever is on disk, so a file that changed
      # after this session read it is refused: the write was composed against
      # bytes that are gone, and the change it would discard was never seen.
      # StrReplace needs no such check, because it matches against the file as
      # it is when it runs.
      def call(path:, content:)
        safely do
          resolved = resolve(path)
          next resolved if resolved.err?

          full = resolved.value!
          if @ground_truth && File.file?(full)
            next stale_read(path, full) if @ground_truth.changed_since_read?(full)
            fresh = if @ground_truth.respond_to?(:fresh_in_current_turn?)
                      @ground_truth.fresh_in_current_turn?(full)
                    else
                      @ground_truth.fresh?(full)
                    end
            next unread_read(path, full) unless fresh
          end

          perm = permit(path)
          next perm if perm.err?

          FileUtils.mkdir_p(File.dirname(full))
          detail_enabled = defined?(Master::Trace::Dmesg) && Master::Trace::Dmesg.detail_enabled?
          old_src = if detail_enabled && File.file?(full)
            begin
              File.binread(full)
            rescue StandardError
              nil
            end
          elsif detail_enabled
            "".b
          end
          result = commit_write(full, content, path:)
          if detail_enabled && !result.err? && old_src
            diff = Master::Trace::Dmesg.diff_head(old_src, content, limit: 6)
            Master::Trace::Dmesg.detail("write_file", "#{path} (#{content.bytesize} bytes)\n#{diff}")
          end
          result
        end
      end

      private

      def stale_read(path, full)
        @bus&.publish("ground_truth:stale", path: full, reason: "write_file_changed")
        Result.err("write refused - #{path} changed since it was read; read it again", category: :policy)
      end

      def unread_read(path, full)
        @bus&.publish("ground_truth:stale", path: full, reason: "write_file_read_missing_or_expired")
        Result.err("write refused - #{path} must be read in this turn with its SHA-256 receipt before replacing it", category: :policy)
      end
    end
  end
end
