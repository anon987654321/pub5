# frozen_string_literal: true

require "json"
require "time"

require_relative "receipt"
require_relative "workstreams"

module Master
  module Convergence
    module Proof
      ROOTS = Master::Convergence::ROOTS

      module_function

      def run(root: Master::REPO_ROOT)
        checks = [
          check_constitution(root),
          check_trees(root),
          check_commands,
          check_wishlist(root),
          check_snapshot_contract(root),
          check_aging(root),
        ]
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

      # Tri-state evidence must not settle into permanent amber. An
      # INCONCLUSIVE row is a wait with a clock: it names the receipt that
      # first dated it, and if no later receipt carries a verdict for the same
      # check before the window closes, the aged row reopens as FAIL citing
      # that receipt. A verdict re-dates the row — a check that went
      # inconclusive again after an answer starts its own window.
      REVIEW_WINDOW_DAYS = 14

      def check_aging(root, now: Time.now.utc)
        aged = aged_inconclusives(root:, now:)
        return pass_row("aging", "no INCONCLUSIVE has outlived its #{REVIEW_WINDOW_DAYS}-day review window") if aged.empty?

        oldest = aged.min_by { |row| row[:dated_at] }
        fail_row("aging", "#{aged.size} INCONCLUSIVE check(s) outlived the #{REVIEW_WINDOW_DAYS}-day window " \
                          "without a verdict; #{oldest[:name]} first dated by receipt #{oldest[:receipt_id]}")
      rescue StandardError => e
        inconclusive_row("aging", "#{e.class}: #{e.message}")
      end

      def aged_inconclusives(root:, now: Time.now.utc, window: REVIEW_WINDOW_DAYS)
        pending = {}
        # Read the complete append-only receipt history one file at a time. A
        # fixed window can forget an unanswered INCONCLUSIVE after enough runs.
        paths = Dir.glob(File.join(root, ".master", "receipts", "convergence-*.json")).sort
        paths.each do |path|
          row = begin
            JSON.parse(File.read(path, encoding: "UTF-8"))
          rescue JSON::ParserError, EncodingError
            nil
          end
          next unless row.is_a?(Hash)

          at = safe_time(row["generated_at"])
          next unless at

          Array(row.dig("details", "checks")).each do |check|
            next unless check.is_a?(Hash)

            name = check["name"]
            case check["state"]
            when "inconclusive"
              pending[name] ||= { dated_at: at, receipt_id: row["id"] }
            when "pass", "fail"
              pending[name] = nil
            end
          end
        end
        pending.filter_map do |name, first|
          next if first.nil?
          next if now - first[:dated_at] <= window * 86_400

          { name:, receipt_id: first[:receipt_id], dated_at: first[:dated_at].iso8601 }
        end
      end

      def safe_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def pass_row(name, detail) = { name:, state: "pass", detail: detail.to_s }
      def fail_row(name, detail) = { name:, state: "fail", detail: detail.to_s }
      def inconclusive_row(name, detail) = { name:, state: "inconclusive", detail: detail.to_s }
    end
  end
end
