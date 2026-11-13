# frozen_string_literal: true

module Master
  module Fix
    # Evidence/action vocabulary for terminal receipts. These terms describe
    # what the run can prove; they are deliberately not workflow terminal
    # states. OutcomePolicy remains the owner of done, plateau, timeout, etc.
    module Outcome
      MEASURED     = :measured
      CHANGED      = :changed
      REJECTED     = :rejected
      INCONCLUSIVE = :inconclusive
      BLOCKED      = :blocked
      RESUMED      = :resumed

      ALL = [
        MEASURED, CHANGED, REJECTED, INCONCLUSIVE, BLOCKED, RESUMED
      ].freeze

      module_function

      def valid?(value)
        ALL.include?(value.to_s.downcase.to_sym)
      rescue StandardError
        false
      end

      def coerce!(value)
        outcome = value.to_s.downcase.to_sym
        return outcome if ALL.include?(outcome)

        raise ArgumentError,
              "unknown /fix evidence outcome #{value.inspect}; use one of #{ALL.join(', ')}"
      end
    end
  end
end
