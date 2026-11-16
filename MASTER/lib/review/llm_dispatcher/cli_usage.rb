# frozen_string_literal: true

require_relative "../../ground/swallow"

module Master
  module Review
    class LLMDispatcher
      # Estimated token usage for CLI lanes without provider-side metering.
      module CliUsage
        private

        # A lane that reports no usage is billed an estimate from the characters it was sent and gave back,
        # marked approximate in the ledger, so its calls still count against the run's budgets.
        def record_estimated_cli_usage(model:, prompt:, reply:)
          return unless @session

          tokens_in = Master::Trace::Session.estimate_tokens(prompt)
          tokens_out = Master::Trace::Session.estimate_tokens(reply)
          tokens = tokens_in + tokens_out
          return if tokens.zero?

          @session.record_cost(0.0, model:, tokens:, approximate: true)
          publish_llm_cost(model:, cost: 0.0, tokens:, tokens_in:, tokens_out:,
                           estimated: true, approximate: true)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CliUsage.record_estimated_cli_usage", model:)
        end
      end
    end
  end
end
