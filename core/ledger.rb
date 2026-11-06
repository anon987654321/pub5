# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module Core
  # The one ledger: append-only JSON lines. It opens with O_APPEND under an
  # exclusive lock and never truncates, seeks or rewrites; a line once written
  # stays. Model calls carry tokens and cost, so a run's spend is a sum over
  # this file, not a number a component reports about itself.
  class Ledger
    attr_reader :path

    def initialize(path)
      @path = File.expand_path(path)
    end

    def append(kind, **fields)
      entry = { "at" => Time.now.utc.iso8601(3), "kind" => kind.to_s }.merge(fields.transform_keys(&:to_s))
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, File::WRONLY | File::APPEND | File::CREAT, 0o600) do |io|
        io.flock(File::LOCK_EX)
        io.write("#{JSON.generate(entry)}\n")
        io.flush
      end
      entry
    end

    def entries
      return [] unless File.exist?(@path)

      File.foreach(@path).map { |line| JSON.parse(line) }
    end

    # Spend over every llm entry. Cost a provider never priced stays unmeasured:
    # it is counted, not guessed as zero.
    def spend
      calls = entries.select { |e| e["kind"] == "llm" }
      {
        "calls" => calls.size,
        "tokens_in" => calls.sum { |e| e["tokens_in"].to_i },
        "tokens_out" => calls.sum { |e| e["tokens_out"].to_i },
        "cost_usd" => calls.sum { |e| e["cost_usd"].to_f }.round(6),
        "unpriced_calls" => calls.count { |e| e["cost_usd"].nil? }
      }
    end
  end
end
