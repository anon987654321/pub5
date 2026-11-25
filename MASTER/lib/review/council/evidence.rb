# frozen_string_literal: true

require "digest"
require "json"

module Master
  module Review
    module Council
      # Evidence envelope shared by every tribunal domain.
      #
      # Probes remain domain-specific. This object records what a probe actually
      # observed and preserves INCONCLUSIVE as a first-class outcome.
      Evidence = Data.define(
        :artifact,
        :domain,
        :status,
        :observations,
        :measurements,
        :structure,
        :anchors,
        :provenance,
      )

      # Reopened rather than given a Data.define block: a constant assigned in that
      # block lands on Council, not on Evidence.
      class Evidence
        STATUSES = %i[observed inconclusive failed].freeze

        def initialize(
          artifact:,
          domain:,
          status: :observed,
          observations: [],
          measurements: {},
          structure: {},
          anchors: [],
          provenance: {}
        )
          status = status.to_sym
          raise ArgumentError, "unknown evidence status: #{status}" unless STATUSES.include?(status)

          super(
            artifact: artifact.to_s,
            domain: domain.to_sym,
            status:,
            observations: Array(observations).map(&:to_s).freeze,
            measurements: measurements.is_a?(Hash) ? measurements.freeze : {},
            structure: structure.is_a?(Hash) ? structure.freeze : {},
            anchors: Array(anchors).map(&:to_s).freeze,
            provenance: provenance.is_a?(Hash) ? provenance.freeze : {},
          )
        end

        def actionable?
          status == :observed && anchors.any? && observations.any?
        end

        def inconclusive?
          status == :inconclusive
        end

        # Compare only the same artifact and probe contract. Numeric deltas
        # are observations, never a verdict about quality.
        def compare(candidate)
          return { status: :inconclusive, reason: "missing actionable evidence" } unless
            candidate.is_a?(Evidence) && actionable? && candidate.actionable?
          return { status: :inconclusive, reason: "different artifact or probe contract" } unless
            artifact == candidate.artifact && domain == candidate.domain &&
            provenance[:probe] && provenance[:probe] == candidate.provenance[:probe] &&
            provenance[:conditions].is_a?(Hash) && !provenance[:conditions].empty? &&
            provenance[:conditions] == candidate.provenance[:conditions] &&
            anchors.sort == candidate.anchors.sort

          deltas = measurements.filter_map do |key, value|
            other = candidate.measurements[key]
            next unless value.is_a?(Numeric) && other.is_a?(Numeric) &&
              value.real? && other.real? && value.finite? && other.finite?

            delta = other - value
            [key, delta] if delta.finite?
          end.to_h
          { status: :observed, deltas:, before: to_h, after: candidate.to_h }
        end

        # Bind observations to producer-supplied artifact fingerprints. The
        # envelope digest protects the record, not the truth of its observations.
        def comparison_receipt(candidate)
          result = compare(candidate)
          return result unless result[:status] == :observed

          digests = [provenance, candidate.provenance].map { |row| row[:artifact_sha256].to_s }
          unless digests.all? { |digest| digest.match?(/\A[0-9a-f]{64}\z/) }
            return { status: :inconclusive, reason: "missing artifact fingerprints" }
          end

          content = JSON.generate(result)
          source = "comparison:#{domain}:#{Digest::SHA256.hexdigest(artifact)[0, 16]}"
          result.merge(receipt: { source:, content:, sha256: Digest::SHA256.hexdigest(content) })
        end

        def to_h
          {
            artifact:,
            domain:,
            status:,
            observations:,
            measurements:,
            structure:,
            anchors:,
            provenance:,
          }
        end

        def prompt
          [
            "EVIDENCE",
            "artifact: #{artifact}",
            "domain: #{domain}",
            "status: #{status}",
            "observations:",
            observations.map { |value| "- #{value}" },
            "measurements:",
            measurements.map { |key, value| "- #{key}: #{value}" },
            "structure:",
            structure.map { |key, value| "- #{key}: #{value}" },
            "anchors:",
            anchors.map { |anchor| "- #{anchor}" },
            "provenance:",
            provenance.map { |key, value| "- #{key}: #{value}" },
          ].flatten.join("\n")
        end
      end
    end
  end
end
