# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module Master
  module Fix
    # AntigenStore — durable memory of failure signatures (ROBUSTNESS_antigen_memory,
    # ROBUSTNESS_immune_pattern).
    #
    # Records veto reasons, high-cost trajectories and defect classes so later
    # probes can be down-weighted or refused early when they match a known
    # antigen at the same high-risk boundary.
    #
    # Storage is append-only JSONL under .master/antigens/. Matching is by
    # normalised signature key (law id + boundary + defect class digest).
    class AntigenStore
      SCHEMA = 1
      DIR = File.join(".master", "antigens")
      FILE = "signatures.jsonl"

      def initialize(root: nil)
        @root = root || (defined?(Master::REPO_ROOT) && Master::REPO_ROOT) || Dir.pwd
        @path = File.join(@root, DIR, FILE)
      end

      # Record a failure signature. Returns the antigen id.
      def record(law:, boundary:, defect_class:, evidence: {}, note: nil, severity: "warning")
        raise ArgumentError, "law required" if law.to_s.empty?
        raise ArgumentError, "boundary required" if boundary.to_s.empty?
        raise ArgumentError, "defect_class required" if defect_class.to_s.empty?

        signature = signature_key(law, boundary, defect_class)
        antigen = {
          "schema_version" => SCHEMA,
          "id" => Digest::SHA256.hexdigest("#{signature}-#{Time.now.to_f}")[0, 16],
          "signature" => signature,
          "law" => law.to_s,
          "boundary" => boundary.to_s,
          "defect_class" => defect_class.to_s,
          "severity" => severity.to_s,
          "evidence" => evidence.is_a?(Hash) ? evidence : {},
          "note" => note,
          "recorded_at" => Time.now.utc.iso8601,
          "hits" => 1,
        }.compact

        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a:UTF-8") { |f| f.puts(JSON.generate(antigen)) }
        antigen["id"]
      end

      # Match a proposed probe against known antigens. Returns matching records
      # (most recent first) or [].
      def match(law:, boundary:, defect_class: nil, limit: 5)
        sig = if defect_class
                signature_key(law, boundary, defect_class)
              else
                prefix = "#{law}|#{boundary}|"
                nil
              end

        recent(limit: 500).select do |a|
          if sig
            a["signature"] == sig
          else
            a["signature"].to_s.start_with?(prefix)
          end
        end.last(limit.to_i).reverse
      end

      # True when a known antigen exists for this exact signature.
      def known?(law:, boundary:, defect_class:)
        !match(law: law, boundary: boundary, defect_class: defect_class, limit: 1).empty?
      end

      def recent(limit: 50)
        return [] unless File.file?(@path)

        File.readlines(@path, encoding: "UTF-8").last(limit.to_i).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      private

      def signature_key(law, boundary, defect_class)
        digest = Digest::SHA256.hexdigest(defect_class.to_s)[0, 12]
        "#{law}|#{boundary}|#{digest}"
      end
    end
  end
end
