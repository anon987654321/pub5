# frozen_string_literal: true

module Master
  module Fix
    class Transaction
      # The durable side of the transaction, re-opening the class defined in
      # fix/transaction.rb: the manifest it persists and reloads, the pending
      # marker that audits its mutations, the task-contract and manifest
      # contracts that guard both, and the recovery replay that restores a
      # crashed pass from that state. All private; the public surface stays in
      # fix/transaction.rb.
      private

      def persist!
        raise "transaction storage path is a symlink" if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, "files"), File.join(@dir, MANIFEST)].any? { |path| File.symlink?(path) }
        manifest = {
          "version" => 1,
          "id" => @id,
          "state" => @state,
          "delivery_head_before" => @delivery_head_before,
          "delivery_head_after" => @delivery_head_after,
          "delivery_marked" => @delivery_marked == true,
          "paths" => @paths,
          "seen" => @seen,
          "snapshots" => @snapshots.transform_values(&:to_h),
        }
        write_atomic(File.join(@dir, MANIFEST), JSON.pretty_generate(manifest) + "\n", mode: 0o600)
      end

      def load_manifest!
        raise "transaction recovery storage is a symlink" if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, "files")].any? { |item| File.symlink?(item) }
        path = File.join(@dir, MANIFEST)
        raise "transaction manifest is a symlink" if File.symlink?(path)
        raise "transaction manifest not found: #{@id}" unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: "UTF-8"))
        validate_manifest!(data)
        @state = data.fetch("state")
        @delivery_head_before = data["delivery_head_before"]
        @delivery_head_after = data["delivery_head_after"]
        @delivery_marked = data["delivery_marked"] == true
        @paths = data.fetch("paths")
        @seen = Hash.new { |hash, key| hash[key] = [] }
        data.fetch("seen").each { |key, values| @seen[key] = values }
        @snapshots = data["snapshots"].to_h.transform_values do |raw|
          Snapshot.new(raw["path"], raw["exists"], raw["kind"].to_sym, raw["mode"], raw["link"], raw["store"])
        end
        true
      rescue JSON::ParserError => e
        raise "transaction manifest is corrupt: #{e.message}"
      end

      def persisted? = File.file?(File.join(@dir, MANIFEST))

      def persisted_state_matches?
        return false if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir, File.join(@dir, MANIFEST)].any? { |path| File.symlink?(path) }
        data = JSON.parse(File.read(File.join(@dir, MANIFEST), encoding: "UTF-8"))
        data["state"] == @state && data["paths"] == @paths && data["seen"] == @seen &&
          data["delivery_head_before"] == @delivery_head_before &&
          data["delivery_head_after"] == @delivery_head_after &&
          data["delivery_marked"] == (@delivery_marked == true) &&
          data["snapshots"] == JSON.parse(JSON.generate(@snapshots.transform_values(&:to_h)))
      rescue StandardError
        false
      end

      def validate_manifest!(data)
        raise "transaction manifest malformed" unless data.is_a?(Hash) && data["version"].to_i == 1 && data["id"] == @id
        state, paths, snapshots, seen = data.values_at("state", "paths", "snapshots", "seen")
        validate_manifest_header!(data, state, paths, snapshots)
        paths.each { |path| validate_manifest_snapshot!(state, path, snapshots[path]) }

        raise "transaction manifest fingerprints malformed" unless seen.is_a?(Hash) && seen.keys.sort == paths.sort && paths.all? { |p| seen[p].is_a?(Array) && seen[p].all? { |v| v.is_a?(String) } }
      end

      def validate_manifest_header!(data, state, paths, snapshots)
        raise "transaction manifest state unsupported" unless %w[open delivering committed rolled_back conflict trace_failed].include?(state)
        raise "transaction manifest delivery mark malformed" unless [nil, true, false].include?(data["delivery_marked"])
        raise "transaction manifest delivery heads malformed" unless data.values_at("delivery_head_before", "delivery_head_after").all? { |head| head.nil? || head.is_a?(String) }
        raise "transaction manifest paths malformed: unsafe or non-canonical path" unless paths.is_a?(Array) && paths.all? { |p| p.is_a?(String) && p != "." && normalize(p) == p }
        raise "transaction manifest snapshot set mismatch" unless snapshots.is_a?(Hash) && snapshots.keys.sort == paths.sort
      end

      def validate_manifest_snapshot!(state, path, item)
        valid = item.is_a?(Hash) && item["path"] == path && %w[missing file symlink].include?(item["kind"]) &&
                (item["kind"] == "missing" ? item["exists"] == false && item["mode"].nil? :
                  item["exists"] == true && item["mode"].is_a?(Integer) && item["mode"].between?(0, 0o7777))
        raise "transaction manifest snapshot invalid: #{path}" unless valid
        if item["kind"] == "symlink"
          raise "transaction manifest snapshot invalid: #{path}" unless symlink_snapshot_contained?(path, item)
        elsif item["kind"] == "file"
          validate_manifest_file_store!(state, path, item)
        else
          raise "transaction manifest snapshot invalid: #{path}" if item["link"] || item["store"]
        end
      end

      def validate_manifest_file_store!(state, path, item)
        store = item["store"].to_s
        dir = File.expand_path(File.join(@dir, "files"))
        valid = item["link"].nil? && File.dirname(File.expand_path(store)) == dir &&
                File.basename(store).match?(/\A#{Regexp.escape(encoded(path))}(?:\.[0-9a-f]{16})?\z/) &&
                !File.symlink?(store) && !File.directory?(store) && (!%w[open delivering].include?(state) || File.file?(store))
        raise "transaction manifest snapshot invalid: #{path}" unless valid
      end

      # A symlink snapshot is restorable only when its link resolves inside the sandbox.
      def symlink_snapshot_contained?(path, item)
        link = item["link"]
        return false unless link.is_a?(String) && item["store"].nil?

        target = File.expand_path(link, File.dirname(File.join(@root, path)))
        path_guard.within(target) == target
      end

      def validate_task_contract_paths!(paths)
        contract = TaskContract.current
        repo_root = File.expand_path(outer_root)
        uncovered = contract ? paths_outside_contract(paths, contract, repo_root) : []
        unless uncovered.empty?
          raise TaskContract::Invalid,
                "transaction paths outside task-contract scope: #{uncovered.first(5).join(", ")}"
        end

        # "New tracked path" is a repository concept. `outer_root` is the
        # transaction's own scope, which is a scratch directory whenever the root
        # lies outside the repo; passing that as the repo root made every path in
        # such a transaction look like an undeclared addition. Only judge paths
        # that can actually be tracked.
        repository = File.expand_path(
          defined?(Master::REPO_ROOT) ? Master::REPO_ROOT : File.expand_path("../../", __dir__)
        )
        return unless inside?(File.expand_path(@root), repository)

        refuse_unapproved_new_paths(paths, contract, repo_root)
      end

      def paths_outside_contract(paths, contract, repo_root)
        Array(paths).reject do |path|
          full = File.expand_path(path, @root)
          next false unless inside?(full, repo_root)

          relative = Pathname.new(full).relative_path_from(Pathname.new(repo_root)).to_s
          TaskContract.covers?(relative, scope: contract.scope)
        end
      end

      def refuse_unapproved_new_paths(paths, contract, repo_root)
        unapproved = Array(paths).filter_map do |path|
          TaskContract.new_path_refusal(File.expand_path(path, @root), contract:, repo_root:)
        end
        return if unapproved.empty?

        raise TaskContract::Invalid,
              "transaction new paths need explicit task-contract.new_paths declarations: #{unapproved.first(3).join("; ")}"
      end

      def encoded(path) = Digest::SHA256.hexdigest(path)[0, 24]

      def pending_marker_path = File.join(@root, ROOT_DIR, ".pending-#{@id}")

      def pending_marker?
        File.exist?(pending_marker_path) || File.symlink?(pending_marker_path)
      rescue SystemCallError
        true
      end

      MARKER_REFUSED = "transaction recovery refused: a lifecycle audit is incomplete; manual review required"

      # Runs under the root lock, so no live transaction is mid-mutation. A marker
      # whose writer is gone is resolved once the manifest loads and validates;
      # one a live process holds, a symlink, or a manifest that does not load
      # stays refused. Answers the refusal, or nil to proceed.
      def resolve_pending_marker!
        label = File.join(ROOT_DIR, File.basename(pending_marker_path))

        refusal = Master::Trace::MutationObserver::PendingMarker.resolve(pending_marker_path, label:) do
          load_manifest!
          "transaction #{@id} manifest loads, state=#{@state}"
        end

        Result.err("#{MARKER_REFUSED}: #{refusal}", category: :infrastructure) if refusal
      end

      def create_pending_marker!(operation)
        path = pending_marker_path
        raise "transaction lifecycle marker is a symlink" if File.symlink?(path)
        Master::Trace::MutationObserver::PendingMarker.write!(path, operation:, subject: @id)
        @pending_marker_owned = true
      end

      def remove_pending_marker!
        path = pending_marker_path
        File.delete(path) if File.exist?(path)
        @pending_marker_owned = false
        true
      end

      # Reached only via Recovery.recover! (load_persisted(...).send(:recover!))
      # -- nothing else calls an instance's own recover! directly, confirmed
      # by grepping every lib/ and test/ caller before making this private.
      def recover!(release_conflicts: false)
        return Result.err("transaction recovery refused: an active transaction holds the root lock", category: :infrastructure) unless acquire_lock(nonblock: true)
        refusal = resolve_pending_marker!
        return refusal if refusal

        load_manifest!
        recover_for_state(release_conflicts:)
      rescue StandardError => e
        emit("fix:transaction_recovery_failed", id: @id, error: e.message)
        Result.err("transaction recovery: #{e.message}", category: :infrastructure)
      ensure
        release_lock
      end

      def recover_for_state(release_conflicts: false)
        case @state
        when "open" then recover_open_state(release_conflicts:)
        when "delivering" then recover_delivering_state
        when "committed", "rolled_back" then recover_terminal_state
        when "conflict" then recover_error_state("transaction recovery found a concurrent edit", :policy)
        when "trace_failed" then recover_error_state("transaction lifecycle audit failed; manual review required", :infrastructure)
        else recover_error_state("unknown transaction state: #{@state}", :infrastructure)
        end
      end

      def recover_delivering_state
        outcome = delivery.recover!
        outcome == :not_committed ? recover_open_state : outcome
      end

      # cleanup! runs for its side effect (removing the transaction directory)
      # and answers nil when its symlink guard skips, so the Result stands alone.
      def recover_terminal_state
        cleanup!
        Result.ok(@state.to_sym)
      end

      def recover_error_state(message, category) = Result.err(message, category:)

      def recover_open_state(release_conflicts: false)
        @active = true
        name_released(release_conflicts!) if release_conflicts

        result = rollback!
        emit("fix:transaction_recovered", id: @id, result: result.to_s)
        result
      end

      def name_released(paths)
        return if paths.empty?

        Master::Trace::Dmesg.status(
          "fix0", "stranded transaction #{@id}: kept #{paths.size} file(s) another writer changed since: " \
                  "#{paths.first(5).join(", ")}"
        )
      end

      # The disk legs of rollback and interrupted-run cleanup: put each
      # snapshot's bytes back, drop replaced files, remove the directory.
      def restore(path, snapshot)
        abs = absolute(path)
        case snapshot.kind
        when :missing
          remove(abs)
        when :symlink
          remove(abs)
          FileUtils.mkdir_p(File.dirname(abs))
          File.symlink(snapshot.link, abs)
        when :file
          FileUtils.mkdir_p(File.dirname(abs))
          content = File.binread(snapshot.store)
          write_atomic(abs, content, mode: snapshot.mode)
        when :other
          raise "cannot restore unsupported path type: #{path}"
        end
      end

      def remove(path)
        File.delete(path) if File.exist?(path) || File.symlink?(path)
      end

      def cleanup!
        return if [File.join(@root, ".master"), File.join(@root, ROOT_DIR), @dir].any? { |path| File.symlink?(path) }
        FileUtils.rm_rf(@dir)
        parent = File.dirname(@dir)
        FileUtils.rmdir(parent) if Dir.exist?(parent) && Dir.empty?(parent)
      rescue SystemCallError
        nil
      end
    end
  end
end
