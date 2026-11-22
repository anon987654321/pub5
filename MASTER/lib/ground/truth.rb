# frozen_string_literal: true

require "digest"

module Master
  module Ground
    # Fresh reads before claims/commits. laws.yml carries no ground_truth_check
    # key, so the age window is the constant below unless the caller passes one.
    class Truth
      Entry = Data.define(:path, :sha256, :read_at, :turn_id)
      DEFAULT_MAX_AGE_SECONDS = 300

      def initialize(max_age_seconds: nil, event_bus: nil)
        @max_age = max_age_seconds || DEFAULT_MAX_AGE_SECONDS
        @bus = event_bus
        @reads = {}
        @writes = {}
        @turn_id = 0
        @contents = Io::ContentCache.new
        @mutex = Mutex.new
      end

      def record_read!(path, content: nil)
        record_observation!(
          path, content:, collection: @reads, event: "ground_truth:read",
          context: "ground_truth.record_read"
        )
      end

      # An owned write is known state, but it is not evidence that the source
      # was read. Keep the provenance separate while allowing same-turn follow-up
      # writes and commit freshness checks to recognize the bytes this process owns.
      def record_written!(path, content: nil)
        record_observation!(
          path, content:, collection: @writes, event: "ground_truth:written",
          context: "ground_truth.record_written"
        )
      end

      # Begin one user-visible turn. Reads made by earlier turns remain useful
      # for history/audit, but cannot authorize a new whole-file replacement.
      def begin_turn!
        @mutex.synchronize { @turn_id += 1 }
      end

      def current_turn_id
        @mutex.synchronize { @turn_id }
      end

      def fresh?(path, content: nil)
        resolved = File.expand_path(path)
        entry = @mutex.synchronize { @reads[resolved] }
        fresh_entry?(resolved, entry, content:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Truth.fresh?")
        false
      end

      def fresh_in_current_turn?(path, content: nil)
        resolved = File.expand_path(path)
        entry, turn_id = @mutex.synchronize { [latest_entry_locked(resolved), @turn_id] }
        return false unless entry && entry.turn_id == turn_id

        fresh_entry?(resolved, entry, content:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Truth.fresh_in_current_turn?")
        false
      end

      def fresh_entry?(resolved, entry, content:)
        return false unless entry
        return false if (Time.now.to_f - entry.read_at) > @max_age

        if content
          Digest::SHA256.hexdigest(content) == entry.sha256
        else
          File.exist?(resolved) && Digest::SHA256.hexdigest(File.read(resolved)) == entry.sha256
        end
      end

      # A file this session read or wrote and whose bytes have not changed since.
      # The receipt retains its original kind, so an owned write never masquerades as a read.
      def recorded_unchanged?(path)
        resolved = File.expand_path(path)
        entry = @mutex.synchronize { latest_entry_locked(resolved) }
        entry && File.exist?(resolved) && @contents.digest(resolved) == entry.sha256
      end

      # True when the latest state observed here (by read or owned write) differs now.
      # A file never observed answers false.
      def changed_since_read?(path)
        resolved = File.expand_path(path)
        entry = @mutex.synchronize { latest_entry_locked(resolved) }
        return false unless entry
        return true unless File.exist?(resolved)

        @contents.digest(resolved) != entry.sha256
      end

      def assert_fresh!(path, reason: "claim_task_complete")
        return Result.ok(path) if fresh?(path)

        @bus&.publish("ground_truth:stale", path:, reason:)
        Result.err("ground_truth: stale read required for #{path} before #{reason}", category: :policy)
      end

      def reset!
        @mutex.synchronize do
          @reads.clear
          @writes.clear
        end
        @contents.clear
      end

      private

      def latest_entry_locked(path)
        [@reads[path], @writes[path]].compact.max_by(&:read_at)
      end

      def record_observation!(path, content:, collection:, event:, context:)
        resolved = File.expand_path(path)
        body = content || File.read(resolved)
        entry = @mutex.synchronize do
          Entry.new(
            path: resolved,
            sha256: Digest::SHA256.hexdigest(body),
            read_at: Time.now.to_f,
            turn_id: @turn_id,
          ).tap { |record| collection[resolved] = record }
        end
        @contents.record(resolved, entry.sha256)
        @bus&.publish(event, path: resolved, sha256: entry.sha256, turn_id: entry.turn_id)
        entry
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context:, path:)
        nil
      end

    end
  end
end
