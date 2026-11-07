# frozen_string_literal: true

module Operator
  # Shared monotonic baseline comparison for imported source lints.
  module BaselineRatchet
    def counts(findings = scan)
      self::BASELINES.keys.to_h do |kind|
        [kind, findings.count { |finding| finding.respond_to?(:kind) && finding.kind.to_s == kind.to_s }]
      end
    end

    def over_baseline(findings = scan)
      counts(findings).filter_map do |kind, count|
        baseline = self::BASELINES.fetch(kind)
        "#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})" if count > baseline
      end
    end
  end
end
