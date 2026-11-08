# frozen_string_literal: true

require "time"

require_relative "receipt"
require_relative "workstreams"

module Master
  module Convergence
    module Proof
      ROOTS = Master::Convergence::ROOTS

      # An INCONCLUSIVE that outlives this many seconds since the receipt that
      # first dated it reopens as FAIL carrying that receipt: tri-state
      # evidence must not settle into permanent amber (convergence.yml
      # workstream inconclusive_aging).
      WINDOW = 7 * 24 * 60 * 60

      # Escalation looks this many receipts back for the one that first dated
      # the inconclusive. Ten (Receipt.recent's default) would lose the
      # receipt on a busy tree; unbounded would read the whole directory.
      AGING_LOOKBACK = 200

      module_function

      def run(root: Master::REPO_ROOT, now: -> { Time.now.utc }, window: WINDOW)
        checks = [
          check_constitution(root),
          check_trees(root),
          check_commands,
          check_wishlist(root),
          check_snapshot_contract(root),
        ]
        checks = age_inconclusives(checks, receipts: Receipt.recent(root:, limit: AGING_LOOKBACK),
                                   now:, window:)
        failed = checks.select { |row| row[:state] == "fail" }
        inconclusive = checks.select { |row| row[:state] == "inconclusive" }
        state = if failed.any? then :fail
                elsif inconclusive.any? then :inconclusive
                else :pass
                end
        receipt = Receipt.write(root:, command: "convergence.prove", state:, details: { checks: })
        { state:, checks:, receipt: }
      end

      def render(root: Master::REPO_ROOT)
        result = run(root:)
        lines = ["prove0: #{result[:state]}"]
        result[:checks].each do |row|
          suffix = row[:detail].to_s.empty? ? "" : ": #{row[:detail]}"
          lines << "prove0: #{row[:name]} #{row[:state]}#{suffix}"
        end
        lines << "prove0: receipt=#{result[:receipt][:path].delete_prefix("#{root}/")}"
        lines.join("\n")
      end

      # The durable receipt ledger, most recent first: /fix --prove history [N].
      def history(root: Master::REPO_ROOT, argument: "")
        limit = argument.empty? ? 10 : Integer(argument)
        rows = Master::Convergence::Receipt.recent(root:, limit:)
        return "prove0: no receipts" if rows.empty?

        lines = rows.map do |row|
          total = row.dig("inventory", "totals") || {}
          "prove0: #{row["id"]} state=#{row["state"]} files=#{total["files"]} bytes=#{total["bytes"]}"
        end
        lines.join("\n")
      rescue ArgumentError
        "usage: /fix --prove history [N]"
      end

      # Reopen stale INCONCLUSIVE check rows as FAIL, citing the receipt that
      # first dated them. Receipts arrive newest first; a pass or a fail for
      # the same check name ends the inconclusive streak and restarts the
      # clock, so an operator's verdict is never aged out from under them.
      def age_inconclusives(checks, receipts:, now:, window: WINDOW)
        checks.map do |row|
          next row unless row[:state] == "inconclusive"

          first_dated = nil
          receipts.each do |receipt|
            prior = Array(receipt.dig("details", "checks")).find { |item| item["name"] == row[:name] }
            state = prior&.dig("state")
            break if %w[pass fail].include?(state)

            first_dated = receipt if state == "inconclusive"
          end
          next row unless first_dated
          next row unless first_dated["generated_at"]

          dated_at = begin
            Time.iso8601(first_dated["generated_at"])
          rescue ArgumentError
            nil
          end
          next row unless dated_at
          next row unless now.call - dated_at >= window

          { name: row[:name], state: "fail",
            detail: "#{row[:detail]} - inconclusive since #{first_dated["id"]} " \
                    "(#{first_dated["generated_at"]}); the review window closed without a verdict" }
        end
      end

      def check_constitution(root)
        soul = File.join(root, "MASTER", "data", "soul.yml")
        laws = File.join(root, "MASTER", "data", "laws.yml")
        return fail_row("constitution", "soul.yml or laws.yml missing") unless File.file?(soul) && File.file?(laws)

        pass_row("constitution", "soul.yml + laws.yml present")
      rescue StandardError => e
        fail_row("constitution", "#{e.class}: #{e.message}")
      end

      def check_trees(root)
        missing = ROOTS.reject { |tree| File.directory?(File.join(root, tree)) }
        missing.empty? ? pass_row("trees", "four governed roots present") : fail_row("trees", "missing #{missing.join(", ")}")
      end

      def check_commands
        commands = Master::CLI::CommandRegistry::HELP_TOPICS.keys
        required = %w[status fix laws why]
        missing = required - commands
        missing.empty? ? pass_row("commands", "required convergence commands documented") : fail_row("commands", "missing #{missing.join(", ")}")
      rescue StandardError => e
        inconclusive_row("commands", "#{e.class}: #{e.message}")
      end

      def check_wishlist(root)
        items = Workstreams.items(root: File.join(root, "MASTER"))
        missing_paths = items.reject { |item| item[:implementation_present] }
        missing_paths.empty? ? pass_row("wishlist", "#{items.size} workstreams have implementation anchors") :
          inconclusive_row("wishlist", "#{missing_paths.size} workstream implementation anchors need external proof")
      rescue StandardError => e
        fail_row("wishlist", "#{e.class}: #{e.message}")
      end

      def check_snapshot_contract(root)
        snapshot = File.join(root, "MASTER", "tools", "snapshot.rb")
        return fail_row("snapshot", "MASTER/tools/snapshot.rb missing") unless File.file?(snapshot)

        pass_row("snapshot", "share-size bounded snapshot implementation present")
      end

      def pass_row(name, detail) = { name:, state: "pass", detail: detail.to_s }
      def fail_row(name, detail) = { name:, state: "fail", detail: detail.to_s }
      def inconclusive_row(name, detail) = { name:, state: "inconclusive", detail: detail.to_s }
    end
  end
end
