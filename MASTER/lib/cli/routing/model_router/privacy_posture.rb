# frozen_string_literal: true

module Master
  module CLI
    module Routing
      class ModelRouter
        # How a lane treats prompt content, and whether it may carry a request
        # tagged :sensitive. The posture is an evidence field, not a guess: a
        # lane earns `anonymous` only from the provider's own written policy,
        # and every hosted lane starts `unknown` until someone cites one. The
        # local bed is `anonymous` because the operator owns the disk the
        # prompt lands on.
        #
        # `anonymous` is the only posture that may carry :sensitive work.
        # `logs_prompts` and `trains_on_data` refuse it by their own names,
        # and `unknown` refuses it because "nobody wrote the policy down" is
        # not consent.
        module PrivacyPosture
          ANONYMOUS      = :anonymous
          LOGS_PROMPTS   = :logs_prompts
          TRAINS_ON_DATA = :trains_on_data
          UNKNOWN        = :unknown

          SENSITIVE_SAFE = [ANONYMOUS].freeze

          module_function

          def parse(value)
            case value.to_s
            when "anonymous"      then ANONYMOUS
            when "logs_prompts"   then LOGS_PROMPTS
            when "trains_on_data" then TRAINS_ON_DATA
            else UNKNOWN
            end
          end

          def allows?(posture, sensitivity)
            return true unless sensitivity == :sensitive

            SENSITIVE_SAFE.include?(posture)
          end
        end
      end
    end
  end
end
