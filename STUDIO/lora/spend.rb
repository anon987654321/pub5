#!/usr/bin/env ruby
# frozen_string_literal: true

# What did the LoRA studio actually spend, and is it inside the envelope?
#
# Every training run appends to a private per-subject ledger
# (.cache/training-spend.jsonl, studio.lora.training_spend.v1) and every film
# render writes a receipt beside it carrying the provider-reported cost when
# the provider reported one. This tool walks those receipts - read-only - and
# sums them per subject per month against billing.monthly_envelope_usd from
# training_standards.yml.
#
#   ruby STUDIO/lora/spend.rb [--month 2026-11] [--json]
#
# The envelope is operator policy and is deliberately unset upstream
# (monthly_envelope_usd: null): the tool reports visibility now and an honest
# NOT_CONFIGURED until the operator chooses a number. Counted costs are
# provider-reported figures, not invoices; receipts without a reported cost
# are listed as unpriced, never guessed.

require "bigdecimal"
require "json"
require "optparse"
require "time"
require "yaml"

module Studio
  module Lora
    module Spend
      ROOT = File.expand_path(__dir__).freeze
      STANDARDS_PATH = File.join(ROOT, "training_standards.yml").freeze
      STANDARDS = YAML.safe_load_file(STANDARDS_PATH, permitted_classes: [], permitted_symbols: [], aliases: false).freeze
      SUBJECT_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\z/.freeze
      FILM_RECEIPT_GLOB = "*.mp4.json"
      WARNING_RATIO = BigDecimal("0.8")

      class Error < StandardError; end

      module_function

      def envelope
        value = STANDARDS.fetch("billing")["monthly_envelope_usd"]
        value.nil? ? nil : BigDecimal(value.to_s)
      end

      # Every cost row found for a subject: training ledger records and film
      # receipts. Rows carry month (YYYY-MM) so any window can aggregate them.
      def rows_for(subject_directory)
        rows = []
        ledger = File.join(subject_directory, ".cache", "training-spend.jsonl")
        if File.file?(ledger) && !File.symlink?(ledger)
          File.readlines(ledger, chomp: true).each do |line|
            next if line.empty?

            record = JSON.parse(line)
            cost = record.dig("spend", "calculated_cost_usd_not_invoice")
            rows << {
              "kind" => "training",
              "month" => month_of(record["recorded_at"]),
              "cost_usd" => cost.nil? ? nil : BigDecimal(cost.to_s),
            }
          rescue JSON::ParserError, ArgumentError
            nil
          end
        end

        Dir[File.join(subject_directory, ".cache", "**", FILM_RECEIPT_GLOB)].sort.each do |receipt|
          data = JSON.parse(File.read(receipt, encoding: "UTF-8"))
          prediction = data["provider_prediction"] || {}
          rows << {
            "kind" => "film",
            "month" => month_of(data["created_at"]),
            "cost_usd" => prediction["actual_cost_usd"].nil? ? nil : BigDecimal(prediction["actual_cost_usd"].to_s),
          }
        rescue JSON::ParserError, ArgumentError
          nil
        end
        rows
      end

      def month_of(timestamp)
        Time.parse(timestamp.to_s).utc.strftime("%Y-%m")
      rescue ArgumentError, TypeError
        "unknown"
      end

      # Pure aggregation so the envelope logic is testable without receipts.
      def summarize(rows, month:, envelope:)
        window = rows.select { |row| row["month"] == month }
        priced = window.filter_map { |row| row["cost_usd"] }
        total = priced.reduce(BigDecimal("0"), :+)
        state = if envelope.nil?
                  "NOT_CONFIGURED"
                elsif total > envelope
                  "EXCEEDED"
                elsif total >= envelope * WARNING_RATIO
                  "WARNING"
                else
                  "WITHIN_ENVELOPE"
                end
        {
          "month" => month,
          "state" => state,
          "priced_receipts" => priced.length,
          "unpriced_receipts" => window.length - priced.length,
          "total_usd" => total.to_s("F"),
          "envelope_usd" => envelope&.to_s("F"),
          "limits" => "Provider-reported costs, not invoices; unpriced receipts are counted but not guessed.",
        }
      end

      def report(month: Time.now.utc.strftime("%Y-%m"))
        subjects = Dir.children(ROOT).sort.select do |entry|
          SUBJECT_NAME.match?(entry) && File.directory?(File.join(ROOT, entry)) && !File.symlink?(File.join(ROOT, entry))
        end
        summaries = subjects.to_h do |name|
          [name, summarize(rows_for(File.join(ROOT, name)), month:, envelope:)]
        end
        {
          "schema" => "studio.lora.spend.v1",
          "read_only" => true,
          "provider_calls" => 0,
          "month" => month,
          "state" => summaries.values.map { |row| row.fetch("state") }.then { |states| worst(states) },
          "subjects" => summaries,
        }
      end

      def worst(states)
        order = %w[EXCEEDED WARNING NOT_CONFIGURED WITHIN_ENVELOPE]
        order.find { |state| states.include?(state) } || "WITHIN_ENVELOPE"
      end

      def run_cli(argv)
        options = { month: nil, json: false }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/spend.rb [--month YYYY-MM] [--json]"
          parser.on("--month YYYY-MM", "Sum one month (default: current)") { |value| options[:month] = value }
          parser.on("--json", "Print the full machine-readable report") { options[:json] = true }
          parser.on("-h", "--help", "Show this help") { puts parser; return 0 }
        end.parse!(argv)

        result = report(month: options[:month] || Time.now.utc.strftime("%Y-%m"))
        if options[:json]
          puts JSON.pretty_generate(result)
        else
          puts "spend #{result.fetch("month")}: #{result.fetch("state")}"
          result.fetch("subjects").each do |name, row|
            puts "  #{name}: $#{row.fetch("total_usd")} across #{row.fetch("priced_receipts")} priced receipts" \
                 "#{row.fetch("unpriced_receipts").positive? ? " (+#{row.fetch("unpriced_receipts")} unpriced)" : ""}" \
                 "#{row.fetch("envelope_usd") ? " of $#{row.fetch("envelope_usd")}" : " (no envelope configured)"}"
          end
        end
        result.fetch("state") == "EXCEEDED" ? 1 : 0
      end
    end
  end
end

exit Studio::Lora::Spend.run_cli(ARGV) if $PROGRAM_NAME == __FILE__
