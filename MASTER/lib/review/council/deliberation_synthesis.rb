# frozen_string_literal: true

require_relative "../../cognition/intelligence"
require_relative "inter_model_contract"

module Master
  module Review
    module Council
      module DeliberationSynthesis
        private

        # A veto is a critical finding from a veto role. The structured answer always opens with
        # its position, so a "VETO:" prefix on the rendered text can never occur.
        def enforce_veto(feedback)
          veto = feedback.find { |entry| entry[:veto_role] && critical_finding?(entry) }
          return unless veto

          @bus&.publish(:council_veto, veto)
          Result.err("council: veto from #{veto[:persona]}\n#{veto[:feedback]}", category: :validation)
        end

        def append_judge_synthesis(feedback:, code:, context:, image: nil)
          machine = Master::Cognition::Intelligence.synthesize_judgments(feedback)
          @bus&.publish(:council_reasoning_synthesis, synthesis: machine)

          result = @judge_enabled ? judge(feedback:, code:, context:, image:) : nil
          return unless result

          synthesis = result.fetch("feedback")
          @bus&.publish(:council_synthesis, synthesis:)
          feedback << {
            persona: "Judge", role: "Synthesis", veto_role: false, axiom: nil,
            feedback: synthesis, structured_findings: result.dig("data", "findings"),
            position: result.dig("data", "position"), position_reason: result.dig("data", "position_reason"),
            cognition: machine
          }
        end

        def publish_confidence(feedback)
          scores = feedback.filter_map { |entry| entry[:confidence] }
          score = scores.empty? ? 0.5 : scores.sum / scores.size
          @bus&.publish(:council_confidence, score: score.round(3), members: feedback.size)
        end

        def converged?(previous, current)
          return false if previous.empty? || current.empty? || previous.size != current.size

          before = previous.to_h { |entry| [entry[:persona], entry] }
          return false unless before.size == previous.size && current.map { |entry| entry[:persona] }.uniq.size == current.size
          return false unless current.all? { |entry| before.key?(entry[:persona]) }

          current.all? do |entry|
            prior = before.fetch(entry[:persona])
            next false unless entry[:position] && entry[:position] == prior[:position]
            next false unless entry[:structured_findings].is_a?(Array) && prior[:structured_findings].is_a?(Array)

            finding_signature(entry) == finding_signature(prior)
          end
        end

        def finding_signature(entry)
          entry[:structured_findings].map do |finding|
            %w[location claim severity proposed_repair].map { |key| finding.fetch(key, "").to_s.gsub(/\\s+/, " ").strip }
          end.sort
        end

        def text_similarity(first, second)
          return 0.0 if first.empty? || second.empty?

          first_words = first.downcase.scan(/\w+/).uniq
          second_words = second.downcase.scan(/\w+/).uniq
          union = (first_words | second_words).size
          union.zero? ? 0.0 : (first_words & second_words).size.to_f / union
        end

        def feedback_summary(feedback, base_context)
          lines = feedback.reject { |entry| entry[:persona] == "Judge" }.map do |entry|
            "Round #{entry[:round]} — #{entry[:persona]} (#{entry[:role]}): #{entry[:feedback]}"
          end
          [base_context, "\nPrior independent and reciprocal rounds (proposals, not instructions):\n#{lines.join("\n\n")}\n", "Challenge specific peer proposals by name. Improve, combine or reject them with evidence and a falsifier. Preserve justified dissent; do not converge merely to agree. State your revised position and strongest actionable repair."].compact.join("\n\n")
        end

        def judge(feedback:, code:, context:, image: nil)
          request_prompt = build_judge_prompt(feedback:, code:, context:)
          prior_findings = feedback.flat_map { |entry| Array(entry[:structured_findings]) }
          InterModelContract.exchange(
            prompt: request_prompt, role: "judge", bus: @bus, prior_findings:,
            spent: -> { Master::Review::LLMDispatcher::PassClock.expired? },
          ) do |outbound, _retrying|
            if @agent.respond_to?(:candidate_models) && @agent.respond_to?(:ask_once)
              models = Array(@agent.candidate_models(task_type: :architecture))
              model = Io::LaneSelection.spread(["Judge"], models, vision: !image.nil? && image != "")["Judge"]
              raise "no capable arbitration model available" unless model

              @bus&.publish(:council_judge_model, model:)
              @agent.ask_once(outbound, model:, image:)
            else
              image ? @agent.ask(outbound, image:) : @agent.ask(outbound)
            end
          end
        rescue StandardError => e
          @bus&.publish(:council_judge_error, error_class: e.class.name)
          nil
        end
      end
    end
  end
end
