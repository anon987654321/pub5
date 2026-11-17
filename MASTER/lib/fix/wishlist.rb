# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "yaml"
require_relative "../ai/orientation"
require_relative "../io/atomic_write"
require_relative "../io/git_operations"
require_relative "../review/scan/semantic_fingerprint"
require_relative "../master/time"
require_relative "wishlist/proof_contract"
require_relative "wishlist/personas"
# The re-opened parts of this class, one responsibility each; every path is
# listed in data/autoload.yml under autoload.reopens_a_constant_defined_elsewhere.
require_relative "wishlist/claims"
require_relative "wishlist/rendering"

module Master
  module Fix
    # Converts the end of a /fix run into a bounded, evidence-linked next-work
    # queue. It proposes; it does not silently edit source. Concrete wishes are
    # surfaced to the next /fix through the orientation layer.
    class Wishlist
      include ::Master::Io::AtomicWrite

      LEDGER_PATH = ".master/fix_wishlist.json"
      SCHEMA = 2
      READABLE_SCHEMAS = [1, 2].freeze
      MAX_NEW_ITEMS = 12
      MAX_PROPOSALS = 96
      BATCH_SIZE = 6
      MAX_ATTEMPTS = 3
      TERMINAL_STATUSES = %w[verified blocked rejected stale superseded].freeze
      AUTO_IMPLEMENTATIONS = %w[next_fix].freeze
      LAW_ID = "CONVERGENCE_WISHLIST"

      class ParseError < StandardError; end

      Law = PassLaw

      def initialize(root:, agent:, event_bus: nil)
        @root = File.expand_path(root)
        @agent = agent
        @bus = event_bus
        @git = Master::Io::GitOperations.new(@root)
      end

      def call(state:, target:, run_id:)
        return "wishlist: skipped - no model" unless @agent.respond_to?(:ask)

        items = draft_items(state:, target:, run_id:)
        added, queued = commit_items(items, state:, target:, run_id:)
        publish_done(items, added, queued, target, state)
        "wishlist: drafted #{items.size}, queued #{queued} -> #{LEDGER_PATH}"
      rescue StandardError => e
        @bus&.publish("wishlist:error", error: e.message, state:, target:)
        "wishlist: #{e.class}: #{e.message}"
      end

      private

      # One persona-collect pass over the rendered orientation, with the
      # single-model fallback when no persona answered.
      def draft_items(state:, target:, run_id:)
        orientation = Master::AI::Orientation.render(root: @root, target:, depth: 2, max_entries: 80)
        base = prompt(orientation:, state:, target:, run_id:)
        items = Personas.collect(agent: @agent, base:, parse: method(:parse), normalize: method(:normalize))
        items = normalize(parse(@agent.ask(base))) if items.empty?
        items.first(MAX_NEW_ITEMS)
      end

      # One locked read-modify-write of the ledger, returning the row counts.
      def commit_items(items, state:, target:, run_id:)
        with_ledger_lock do
          ledger = load_ledger
          added = merge_new_items!(ledger, items, state:, target:, run_id:)
          save_ledger(ledger)

          queued = ledger["proposals"].count do |item|
            item["status"] == "queued" && AUTO_IMPLEMENTATIONS.include?(item["implementation"])
          end
          [added, queued]
        end
      end

      def publish_done(items, added, queued, target, state)
        @bus&.publish(
          "wishlist:done",
          drafted: items.size,
          added:,
          queued:,
          target: relative(target),
          state:,
        )
      end

      def ledger_path
        File.join(@root, LEDGER_PATH)
      end

      # One lock covers the full ledger read-modify-write transaction.
      # Atomic rename prevents partial JSON, not lost updates.
      def with_ledger_lock(&block)
        directory_stat = prepare_ledger_directory
        directory = File.dirname(ledger_path)
        group_shared = (directory_stat.mode & 0o020).positive?
        lock_mode = ledger_lock_mode(group_shared)
        lock_path = ledger_lock_path
        File.open(lock_path, ledger_lock_flags, lock_mode) do |file|
          opened = settle_lock_permissions(file, lock_mode)
          assert_lock_policy(opened, directory_stat, group_shared, lock_mode)
          assert_lock_path_stable(lock_path, opened)
          hold_ledger_lock(file, directory, directory_stat, lock_path, group_shared, opened, &block)
        end
      rescue SystemCallError => e
        raise IOError, "cannot safely lock wishlist ledger: #{e.class}: #{e.message}"
      end

      # Creates the ledger directory and proves it is a real, stable,
      # non-world-writable home for the lock.
      def prepare_ledger_directory
        directory = File.dirname(ledger_path)
        FileUtils.mkdir_p(directory, mode: 0o700)
        directory_stat = File.lstat(directory)
        unless directory_stat.directory? && !directory_stat.symlink? &&
               (directory_stat.mode & 0o002).zero?
          raise IOError, "wishlist directory must be a stable, real, non-world-writable directory"
        end

        directory_stat
      end

      # The lock file inherits the directory's sharing policy.
      def ledger_lock_mode(group_shared)
        group_shared ? 0o660 : 0o600
      end

      # NOFOLLOW where the platform has it, so a planted symlink is refused.
      def ledger_lock_flags
        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        flags
      end

      def ledger_lock_path
        lock_path = "#{ledger_path}.lock"
        raise IOError, "refusing symlinked wishlist lock" if File.symlink?(lock_path)

        lock_path
      end

      # Re-chmods an existing lock file we own so it matches the current policy.
      def settle_lock_permissions(file, lock_mode)
        opened = file.stat
        if opened.uid == Process.uid && (opened.mode & 0o777) != lock_mode
          file.chmod(lock_mode)
          opened = file.stat
        end
        opened
      end

      # The lock must be owner-only or group-shared exactly as the directory is;
      # anything looser means someone planted a permissive file.
      def assert_lock_policy(opened, directory_stat, group_shared, lock_mode)
        permissions = opened.mode & 0o777
        shared_permissions = group_shared ?
          (permissions & 0o060) == 0o060 && opened.gid == directory_stat.gid :
          (permissions & 0o070).zero?
        unless opened.file? && opened.nlink == 1 && (permissions & 0o007).zero? &&
               (permissions & 0o600) == 0o600 && shared_permissions
          raise IOError, "wishlist lock permissions do not match its directory's sharing policy"
        end
      end

      # The lock path must still resolve to the very file this handle opened.
      def assert_lock_path_stable(lock_path, opened)
        current = File.lstat(lock_path)
        return if current.file? && !current.symlink? && current.dev == opened.dev && current.ino == opened.ino

        raise IOError, "wishlist lock path changed while opening"
      end

      # Blocks on the exclusive flock, re-proves the directory and lock identity
      # after the wait, yields, and always releases before the handle closes.
      def hold_ledger_lock(file, directory, directory_stat, lock_path, group_shared, opened, &block)
        raise IOError, "could not acquire wishlist ledger lock" unless file.flock(File::LOCK_EX)

        begin
          assert_lock_held(directory, directory_stat, lock_path, group_shared, opened)
          yield
        ensure
          file.flock(File::LOCK_UN)
        end
      end

      # After blocking on flock, the directory and the lock must still be the
      # ones this handle was opened against.
      def assert_lock_held(directory, directory_stat, lock_path, group_shared, opened)
        current_directory = File.lstat(directory)
        current = File.lstat(lock_path)
        current_group_shared = (current_directory.mode & 0o020).positive?
        unless current_directory.directory? && !current_directory.symlink? &&
               current_directory.dev == directory_stat.dev && current_directory.ino == directory_stat.ino &&
               current_directory.gid == directory_stat.gid && current_group_shared == group_shared &&
               (current_directory.mode & 0o002).zero? &&
               current.file? && !current.symlink? && current.nlink == 1 &&
               current.dev == opened.dev && current.ino == opened.ino
          raise IOError, "wishlist ledger lock identity changed while waiting"
        end
      end

      def load_ledger
        return { "schema" => SCHEMA, "proposals" => [] } unless File.file?(ledger_path)

        data = JSON.parse(File.read(ledger_path, encoding: "UTF-8"))
        raise "wishlist ledger schema #{data["schema"]} is unsupported" unless READABLE_SCHEMAS.include?(data["schema"].to_i)
        raise "wishlist ledger proposals must be an array" unless data["proposals"].is_a?(Array)

        data["schema"].to_i == SCHEMA ? data : Personas.migrate!(data)
      rescue JSON::ParserError => e
        raise "wishlist ledger is corrupt: #{e.message}"
      end

      def save_ledger(data)
        FileUtils.mkdir_p(File.dirname(ledger_path))
        write_atomic(ledger_path, JSON.pretty_generate(data) + "\n", mode: 0o600)
      end

      def merge_new_items!(ledger, items, state:, target:, run_id:)
        now = Master::Clock.utc_now.iso8601
        basis_head = @git.head.to_s
        added = 0

        items.each do |item|
          next if absorbed?(ledger, item)

          ledger["proposals"] << ledger_row(item, state:, target:, run_id:, now:, basis_head:)
          added += 1
        end

        prune!(ledger)
        added
      end

      # An open row that already is this wish takes the new names instead of a
      # second row; true when the item was absorbed rather than appended.
      def absorbed?(ledger, item)
        fingerprint = proposal_fingerprint(item)
        Personas.absorb!(ledger["proposals"], item.merge("fingerprint" => fingerprint))
      end

      def ledger_row(item, state:, target:, run_id:, now:, basis_head:)
        fingerprint = proposal_fingerprint(item)
        item.merge(
          "uid" => "#{item["id"]}-#{fingerprint[0, 12]}",
          "fingerprint" => fingerprint,
          "status" => "queued",
          "attempts" => 0,
          "created_at" => now,
          "generated_by_run" => run_id.to_s,
          "generated_state" => state.to_s,
          "target" => relative(target),
          "basis_head" => basis_head,
          "anchor_sha256" => anchor_sha256(item["anchor"].to_s),
        )
      end

      def prune!(ledger)
        rows = ledger["proposals"]
        return if rows.size <= MAX_PROPOSALS

        terminal = rows.select { |proposal| TERMINAL_STATUSES.include?(proposal["status"].to_s) }
        drop = [rows.size - MAX_PROPOSALS, terminal.size].min
        ledger["proposals"] = rows - terminal.first(drop)
        ledger["proposals"] = ledger["proposals"].last(MAX_PROPOSALS) if ledger["proposals"].size > MAX_PROPOSALS
      end

      def proposal_fingerprint(item)
        Digest::SHA256.hexdigest(
          [
            item["id"],
            item["title"],
            item["anchor"],
            item["change"],
            item["evidence"],
            Array(item["proof"]).join("|"),
          ].join("\n"),
        )
      end

      def anchor_sha256(anchor)
        file = anchor_file(anchor)
        file ? Digest::SHA256.file(file).hexdigest : nil
      end

      def anchor_file(anchor)
        path, line = anchor.to_s.split(":", 2)
        return unless path && line.to_s.match?(/\A\d+\z/)

        file = File.expand_path(path, @root)
        return unless inside_root?(file) && File.file?(file)

        file
      end

      def anchor_in_target?(anchor, target)
        target = File.expand_path(target.to_s, @root)
        anchor == target || anchor.start_with?("#{target}#{File::SEPARATOR}")
      end

      def inside_root?(path)
        full = File.expand_path(path)
        full == @root || full.start_with?("#{@root}#{File::SEPARATOR}")
      end

      def relative(path)
        full = File.expand_path(path.to_s, @root)
        return "." if full == @root
        return path.to_s unless full.start_with?("#{@root}#{File::SEPARATOR}")

        full.delete_prefix("#{@root}#{File::SEPARATOR}")
      end

    end
  end
end
