# frozen_string_literal: true

module Master
  module CLI
    module Routing
      class ModelRouter
        # Keeps a request inside the target model's context window. A hosted
        # lane with a large window failing over onto a small local bed used to
        # die at dispatch with the provider's own overflow error; fitting the
        # history to the target before the call turns that dead end into a
        # degraded-but-answering turn. Newest messages win: the oldest turns
        # are dropped first, and system rows always ride along.
        #
        # The estimate is chars/4 — deliberately the same crude constant the
        # context-pressure banding shares — never a tokenizer. It errs large,
        # which is the safe direction for a budget: an over-estimate compacts
        # a little early, an under-estimate raises at the provider.
        module ContextBudget
          SAFE_MARGIN = 0.85
          CHARS_PER_TOKEN = 4

          # Raised in strict mode only. The safe mode compacts instead; a
          # caller that cannot degrade (an operation with a hard floor on
          # earlier turns) selects strict and rescues this as its own
          # invalid_request.
          class Overflow < StandardError; end

          module_function

          def fit(messages, window_tokens, mode: :safe)
            limit = window_tokens.to_i
            return messages unless limit.positive?

            budget = (limit * SAFE_MARGIN).to_i
            return messages if estimate(messages) <= budget
            raise Overflow, "prompt needs ~#{estimate(messages)} tokens, window is #{limit}" if mode == :strict

            compact(messages, budget)
          end

          def estimate(messages)
            Array(messages).sum { |message| token_count(message) }
          end

          def token_count(message)
            text = message.is_a?(Hash) ? message[:content].to_s : message.to_s
            [1, (text.length / CHARS_PER_TOKEN.to_f).ceil].max
          end

          def compact(messages, budget)
            system, rest = Array(messages).partition { |m| m.is_a?(Hash) && m[:role].to_s == "system" }
            kept = []
            remaining = budget - estimate(system)

            rest.reverse_each do |message|
              cost = token_count(message)
              break if cost > remaining

              kept.unshift(message)
              remaining -= cost
            end

            system + kept
          end
        end
      end
    end
  end
end
