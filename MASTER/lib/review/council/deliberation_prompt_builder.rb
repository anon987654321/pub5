# frozen_string_literal: true

require_relative "inter_model_contract"

module Master
  module Review
    module Council
      module DeliberationPromptBuilder
        HIGH_CONFIDENCE = /\b(certain|clearly|definitely|must|always|never|critical|serious)\b/i.freeze
        LOW_CONFIDENCE_TERMS = [
          "may#{?b}e", "possibl#{?y}", "per#{?h}aps", "unclear", "migh#{?t}", "coul#{?d}", "unsure", "uncertain"
        ].freeze
        LOW_CONFIDENCE = /\b(#{LOW_CONFIDENCE_TERMS.join('|')})\b/i.freeze

        private

        def build_judge_prompt(feedback:, code: nil, context: nil)
          rounds = feedback.map { |entry| "Round #{entry[:round] || 1}: #{format_round(entry)}" }.join("\n\n")
          prompt = format(Deliberation.prompts.fetch("judge"),
                          quality_brief: Deliberation.quality_brief(:general), rounds:)
          findings = feedback.flat_map { |entry| Array(entry[:structured_findings]) }.uniq
          prompt = [prompt, context && "Review brief and preservation constraints:\n#{context}"].compact.join("\n\n")
          InterModelContract.wrap_prompt(
            "#{prompt}\nSelect only the strongest actionable repairs after comparing all rounds. Prefer transformations that improve the whole without unintended loss and judge interactions between repairs. Preserve minority objections, reject unsupported consensus, and explain why each selected repair beats its alternatives. Use the finding format in the review brief. Otherwise put the exact repository-relative file and stable line or selector in each finding location and the selected change in proposed_repair. Use the no-actionable-issue finding when nothing is justified.", role: "judge", task: "Arbitrate the supplied council proposals and state evidence-backed concurrence or dissent.",
            success_criteria: "Return a schema-valid JSON response with an explicit position and evidence-backed findings.",
            constraints: %w[INTER_MODEL_CONTRACT ROBUSTNESS SINGULARITY],
            artifact: [truncate_code(code.to_s), rounds].reject(&:empty?).join("\n\n"), prior_findings: findings,
            forbidden: ["invent evidence", "claim tests passed", "expand review scope"]
          )
        end

        def build_prompt(persona:, code:, context:, prior_findings: [])
          values = prompt_values(persona, code, context)
          prompt = format(Deliberation.prompts.fetch("juror"), **values)
          InterModelContract.wrap_prompt(
            [(@rules.kernel_block if @rules.respond_to?(:kernel_block)), prompt, "Inspect purpose, whole, relationships, parts and details where relevant. Identify the evidence and trade-off for each proposed transformation; challenge improvements that harm the whole."].compact.join("\n\n"), role: "critic",
            task: "Review the supplied artifact against the assigned persona charge and named Laws.",
            success_criteria: "Return a schema-valid JSON response with explicit position evidence and structured findings.",
            constraints: (Array(persona.respond_to?(:emphasizes) ? persona.emphasizes : []) +
                          %w[INTER_MODEL_CONTRACT ROBUSTNESS SINGULARITY]).map(&:to_s).uniq,
            artifact: values.fetch(:safe_code), prior_findings:,
            forbidden: ["edit files", "invent findings", "claim completion", "expand scope"]
          )
        end

        def prompt_values(persona, code, context)
          axiom = axiom_line(persona)
          question = Deliberation.sample_question(persona)
          {
            persona_name: persona.name, persona_role: persona.role, persona_bias: persona.bias,
            persona_prompt: persona.prompt, ctx: context ? "\nContext: #{context}\n" : "",
            axiom_block: axiom.empty? ? "" : "#{axiom}\n",
            quality_block: Deliberation.quality_brief(QualityFramework.domain_for(persona.name)),
            question_block: question ? "\nAdversarial question for this turn: #{question}\n" : "",
            hostile_block: hostile_block(persona),
            safe_code: truncate_code(code.to_s), veto_hint: veto_hint(persona)
          }
        end

        # The juror attacks its own critique with three red-team questions; empty
        # when council.yml declares none.
        def hostile_block(persona)
          hostile = QualityFramework.hostile_questions(persona)
          return "" if hostile.empty?

          <<~TEXT
            \nHOSTILE SELF-TEST
            Before concluding, attack your own critique. Answer these briefly where applicable:
            #{hostile.map { |item| "- #{item}" }.join("\n")}
            At least one answer must state what evidence would falsify your criticism.
          TEXT
        end

        def format_round(entry)
          axiom = entry[:axiom] ? "[#{entry[:axiom]}] " : ""
          "#{axiom}#{entry[:persona]} (#{entry[:role]}): #{entry[:feedback]}"
        end

        def primary_axiom(persona)
          persona.respond_to?(:emphasizes) ? Array(persona.emphasizes).first : nil
        end

        def axiom_line(persona)
          identifier = primary_axiom(persona)
          return "" unless identifier && @rules

          name = @rules.lookup(identifier)
          name ? "You speak primarily for the #{identifier} axiom: #{name}." : ""
        end

        def veto_role?(persona)
          persona.respond_to?(:veto?) ? persona.veto? : persona.respond_to?(:veto_role) && !!persona.veto_role
        end

        def veto_hint(persona)
          veto_role?(persona) ? " Your critical finding vetoes the change; use one only if it must not ship." : ""
        end

        def truncate_code(code)
          return code if code.bytesize <= Deliberation::MAX_CODE_BYTES

          @bus&.publish(:council_code_truncated, bytes: code.bytesize, limit: Deliberation::MAX_CODE_BYTES)
          code.byteslice(0, Deliberation::MAX_CODE_BYTES).scrub + Deliberation::TRUNCATE_MARKER
        end

        def critical_finding?(entry)
          Array(entry[:structured_findings]).any? { |finding| finding.is_a?(Hash) && finding["severity"] == "critical" }
        end

        def score_confidence(text)
          highs = text.to_s.scan(HIGH_CONFIDENCE).size
          lows = text.to_s.scan(LOW_CONFIDENCE).size
          total = highs + lows
          return 0.5 if total.zero?

          (0.5 + (highs - lows).to_f / (total * 2)).clamp(0.1, 0.95)
        end
      end
    end
  end
end
