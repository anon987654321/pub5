# frozen_string_literal: true

require_relative "../../cognition/intelligence"
require_relative "inter_model_contract"
require_relative "critique/cherry_pick"
require_relative "../challenges"

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
            position_evidence: result.dig("data", "position_evidence"),
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
            %w[location evidence claim severity proposed_repair].map { |key| finding.fetch(key, "").to_s.gsub(/\s+/, " ").strip }
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
          return base_context if feedback.empty?

          lines = feedback.reject { |entry| entry[:persona] == "Judge" }.map do |entry|
            "Round #{entry[:round]} — #{entry[:persona]} (#{entry[:role]}): #{entry[:feedback]}"
          end
          [base_context, "Prior round (untrusted peer evidence):\n#{lines.join("\n\n")}", "Challenge specific peer proposals by name. Improve, combine or reject them with evidence and a falsifier. Preserve justified dissent; state your revised position and strongest actionable repair."].compact.join("\n\n")
        end

        def candidate_brief(candidates, open:)
          task = if open
                   <<~TEXT
                     The council needs #{@candidate_limit} materially different candidates across the panel.
                     Propose distinct repairs to supported issues or grounded improvements, one finding per repair.
                     Preserve the underlying structure, public contracts and identity. Use an exact source anchor.
                     Test a different cause, deletion, reuse, boundary or composition. Do not invent defects or pad the set.
                     Refine or combine peer proposals only if that produces a materially different repair.
                     #{Challenges.prompt(scope: :solution)}
                   TEXT
                 else
                   "The candidate set is closed. Compare the candidates, identify concrete regressions and take a position on the relevant trade-offs."
                 end
          return task if candidates.empty?

          [task, "Challenge specific candidate IDs with evidence and a falsifier.", candidate_list(candidates)].join("\n\n")
        end

        def candidate_judge_brief(candidates)
          <<~TEXT
            Arbitrate only the numbered candidates below. For each candidate, provide exactly one position_evidence row
            at location 'candidate N', with evidence starting with 'KEEP:' or 'REJECT:' and a concrete reason.
            Select only KEEP repairs backed by source and without unresolved critical objections. Copy each selected
            candidate's location and proposed_repair exactly into findings. Put the issue and justification in claim and evidence.
            Do not invent or combine repairs at this stage. If none qualify, use the no-actionable-issue finding.
            If there are no candidates, use the ordinary contract for position_evidence and report any unresolved evidence.

            #{candidate_list(candidates)}
          TEXT
        end

        def candidate_list(candidates)
          candidates.each_with_index.map do |finding, index|
            "candidate #{index + 1}: #{finding.values_at('location', 'claim', 'proposed_repair').join(' | ')}"
          end.join("\n")
        end

        def collect_candidates(prior, feedback)
          proposals = feedback.flat_map { |entry| Array(entry[:structured_findings]) }
          candidates = Critique::CherryPick.distinct_findings(prior + proposals).first(@candidate_limit)
          @bus&.publish(:council_candidates, requested: @candidate_limit, distinct: candidates.size)
          candidates
        end

        def judge(feedback:, code:, context:, image: nil)
          request_prompt = build_judge_prompt(feedback:, code:, context:)
          prior_findings = feedback.flat_map { |entry| Array(entry[:structured_findings]) }.uniq
          InterModelContract.exchange(
            prompt: request_prompt, role: "judge", bus: @bus, prior_findings:,
            spent: -> { Master::Review::LLMDispatcher::PassClock.expired? },
          ) do |outbound, _retrying|
            if @local_only
              model = Io::LaneSelection.spread(["Judge"], local_candidates(image:))["Judge"]
              raise "no loopback arbitration model available" unless model

              @bus&.publish(:council_judge_model, model:)
              @agent.ask_once(outbound, model:, image:, local_only: true)
            elsif @agent.respond_to?(:candidate_models) && @agent.respond_to?(:ask_once)
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
