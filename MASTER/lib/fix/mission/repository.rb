# frozen_string_literal: true

module Master
  module Fix
    class Mission
      # Repository custody receipts, re-opening the class defined in
      # fix/mission.rb: the read-side view of still-valid write receipts, the
      # push ledger, and the commit leg that retires receipts once Git holds
      # the content, plus the path sandbox they all judge paths with.
      # Durable content receipts let the next bounded attempt continue the
      # same authorised task without treating a fresh process as a new grant.
      # Every read re-hashes the live file; absent, replaced or symlinked paths
      # lose their receipt rather than inherit stale authority.
      def repository_writes(repository_root:)
        repo = File.realpath(repository_root)
        record = @record || self.class.current(root: @root)
        return {} unless record && record["repository_write_root"] == repo

        (record["repository_writes"] || {}).each_with_object({}) do |(path, digest), found|
          full = repository_full_path(path, repo)
          next unless full && Digest::SHA256.file(full).hexdigest == digest

          found[path] = digest
        end
      rescue SystemCallError, ArgumentError
        {}
      end

      def record_repository_push!(remote:, branch:, commit:)
        return false unless remote.to_s == "origin" && branch.to_s == "main"
        return false unless commit.to_s.match?(/\A[0-9a-f]{40}\z/i)

        with_lock do
          load_writable_unlocked!
          return false unless @record && @record["origin"].to_s == "backlog"

          pushes = @record["repository_pushes"] ||= []
          pushes << { "remote" => "origin", "branch" => "main", "commit" => commit.to_s,
                      "pushed_at" => now }
          @record["repository_pushes"] = pushes.uniq { |row| row["commit"] }.last(32)
          @record["last_seen_at"] = now
          persist!
        end
        emit("mission:repository_push", id: @id, remote: "origin", branch: "main", commit:)
        true
      rescue ArgumentError, TypeError
        false
      end

      def record_repository_commit!(expected_hashes:, repository_root:)
        repo = File.realpath(repository_root)
        receipts = expected_hashes.is_a?(Hash) ? expected_hashes : {}
        with_lock do
          load_writable_unlocked!
          return false unless @record && @record["repository_write_root"] == repo

          writes = @record["repository_writes"] ||= {}
          receipts.each do |path, digest|
            relative = repository_relative_path(path, repo)
            next unless relative && writes[relative] == digest.to_s

            full = File.join(repo, relative)
            writes.delete(relative) if Digest::SHA256.file(full).hexdigest == digest.to_s
          end
          @record["last_seen_at"] = now
          persist!
        end
        true
      rescue SystemCallError, ArgumentError => error
        emit("mission:commit_receipt_refused", id: @id, reason: error.class.name)
        false
      end

      private

      def repository_relative_path(path, repository_root)
        value = path.to_s
        return if value.empty? || value.include?("\0") || value.split(%r{[\\/]}).include?("..")

        full = File.expand_path(value, repository_root)
        return unless full.start_with?(repository_root + File::SEPARATOR)
        return if full.split(File::SEPARATOR).include?(".git")
        return unless File.file?(full) && !File.symlink?(full)

        real = File.realpath(full)
        return unless real.start_with?(repository_root + File::SEPARATOR)

        real.delete_prefix(repository_root + File::SEPARATOR).tr(File::SEPARATOR, "/")
      rescue ArgumentError, SystemCallError
        nil
      end

      def repository_full_path(path, repository_root)
        relative = repository_relative_path(path, repository_root)
        relative && File.join(repository_root, relative)
      end
    end
  end
end
