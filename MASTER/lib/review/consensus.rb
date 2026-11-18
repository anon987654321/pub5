# frozen_string_literal: true

require_relative "../trace/causal_trace"

require "json"

module Master
  module Review
    class Consensus
      Vote = Struct.new(:model, :approved, :reason, keyword_init: true)
      MIN_INDEPENDENT_FAMILIES = 2
      Readiness = Data.define(:state, :detail) do
        def ready? = state == :pass
      end

      # The fix jury must be independently seatable before /fix spends its
      # repair budget. Exclude each possible author family in turn and require
      # both the configured voter quorum and the independent-family floor.
      # A pending or failed probe is never evidence that the jury is ready.
      def self.jury_readiness(router: nil, root: Master::ROOT)
        models = Array(default_models).map(&:to_s).reject(&:empty?).uniq
        quorum = Integer(default_quorum)
        return Readiness.new(state: :fail, detail: "configured pool has #{models.size} model(s), quorum is #{quorum}") if models.size < quorum

        router ||= Master::CLI::Routing::ModelRouter.new(
          config: Master::Ground::Config.new(root), root: root,
        )
        reasons = models.to_h { |model| [model, router.unreachable_reason(model, wait: true)] }
        pending = reasons.select { |_model, reason| reason.to_s.start_with?("checking ") }
        unless pending.empty?
          detail = pending.map { |model, reason| "#{model}: #{reason}" }.join("; ")
          return Readiness.new(state: :unmeasured, detail: "provider probe did not finish: #{detail}")
        end

        reachable = reasons.select { |_model, reason| reason.nil? }.keys
        families = models.map { |model| model_family(model) }.uniq
        blocked = families.filter_map do |author_family|
          voters = reachable.reject { |model| model_family(model) == author_family }
          voter_families = voters.map { |model| model_family(model) }.uniq
          next if voters.size >= quorum && voter_families.size >= MIN_INDEPENDENT_FAMILIES

          "#{author_family} author leaves #{voters.size}/#{quorum} voters across #{voter_families.size}/#{MIN_INDEPENDENT_FAMILIES} families"
        end

        unavailable = reasons.filter_map { |model, reason| "#{model}: #{reason}" unless reason.nil? }
        unless blocked.empty?
          detail = blocked.join("; ")
          detail += "; unavailable: #{unavailable.join('; ')}" unless unavailable.empty?
          return Readiness.new(state: :fail, detail:)
        end

        detail = "#{reachable.size}/#{models.size} reachable; quorum #{quorum} and #{MIN_INDEPENDENT_FAMILIES} independent families survive every author-family exclusion"
        detail += "; unavailable but redundant: #{unavailable.join('; ')}" unless unavailable.empty?
        Readiness.new(state: :pass, detail:)
      rescue StandardError => error
        Readiness.new(state: :unmeasured, detail: "#{error.class}: #{error.message.to_s.lines.first.to_s.strip}")
      end

      VOTE_SCHEMA = {
        type: "object",
        additionalProperties: false,
        required: %w[approved reason],
        properties: {
          approved: { type: "boolean" },
          reason: { type: "string", minLength: 1 },
        },
      }.freeze
      MODEL_FAMILIES = [
        [/claude|anthropic/i, "anthropic"],
        [/grok|xai/i, "xai"],
        [/kimi|moonshot/i, "moonshot"],
        [/deepseek/i, "deepseek"],
        [/qwen|tongyi/i, "qwen"],
        [/glm|zhipu|zai/i, "zhipu"],
        [/gemini|gemma|google/i, "google"],
        [/codex|gpt-|openai|(?:^|[^a-z0-9])o[1-9](?:-|$)/i, "openai"],
        [/llama|meta-llama/i, "meta"],
        [/mistral|codestral/i, "mistral"],
        [/nemotron|nvidia/i, "nvidia"],
        [/minimax/i, "minimax"],
        [/cohere|command-r/i, "cohere"],
        [/perplexity|sonar-/i, "perplexity"],
      ].freeze

      def self.model_family(model)
        id = model.to_s.downcase
        match = MODEL_FAMILIES.find { |pattern, _family| pattern.match?(id) }
        return match.last if match

        provider = if defined?(Master::Io::LaneSelection) && Master::Io::LaneSelection.respond_to?(:provider)
                     Master::Io::LaneSelection.provider(id)
                   else
                     id.split(":", 2).first
                   end
        provider.to_s.empty? ? "unknown" : "provider:#{provider}"
      end

      # models.yml three_mirror_redundancy.pool is the one source. This held a
      # copy of the three ids under a comment asking the next reader to keep the
      # two in step, which is a list where the next model swapped in one place
      # leaves the other voting with a model nothing else routes to.
      def self.default_models
        return Master.three_mirror_pool unless ENV["MASTER_LOCAL_ONLY"] == "1"

        Array(Master.models_config(root: Master::ROOT).dig("models", "local"))
          .filter_map { |row| row["id"].to_s unless row["id"].to_s.end_with?(":cloud", "-cloud") }
          .first(3)
          .freeze
      end

      # models.yml three_mirror_redundancy.quorum, beside the pool it counts.
      def self.default_quorum
        Integer(Master.models_config(root: Master::ROOT).dig("three_mirror_redundancy", "quorum"))
      end

      def initialize(agent:, event_bus: nil, models: nil, quorum: nil)
        models ||= self.class.default_models
        @agent = agent
        @bus = event_bus
        @models = Array(models).reject(&:empty?)
        @quorum = quorum.to_i.positive? ? quorum.to_i : self.class.default_quorum
      end

      def approve_fix?(prompt:, candidate:, violation:, author_models: [])
        authors = Array(author_models).map(&:to_s).reject(&:empty?).uniq
        author_families = authors.map { |model| self.class.model_family(model) }.uniq
        excluded = @models.select { |model| author_families.include?(self.class.model_family(model)) }
        eligible = @models - excluded
        reviewer_families = eligible.map { |model| self.class.model_family(model) }.uniq
        if authors.any? && (eligible.size < @quorum || reviewer_families.size < MIN_INDEPENDENT_FAMILIES)
          @bus&.publish(
            "consensus:blocked",
            reason: :insufficient_independent_reviewers,
            author_models: authors,
            excluded_models: excluded,
            eligible_models: eligible,
            reviewer_families:,
            quorum: @quorum,
            minimum_families: MIN_INDEPENDENT_FAMILIES,
          )
          Master::Trace::CausalTrace.step(
            kind: :decision, name: "consensus.approve_fix",
            input: { law: violation[:law].to_s, severity: violation[:severity].to_s,
                     author_families: author_families.size, reviewer_families: reviewer_families.size,
                     quorum: @quorum },
            output: { approved: false, reason: "insufficient_independent_reviewers" },
          )
          return false
        end

        votes = eligible.map { |model| vote(model, prompt:, candidate:, violation:) }
        approvals = votes.count(&:approved)
        approved = approvals >= @quorum
        dissent = votes.reject(&:approved)
        @bus&.publish(
          "consensus:result",
          approved:,
          approvals:,
          quorum: @quorum,
          author_models: authors,
          excluded_models: excluded,
          reviewer_families:,
          models: votes.map(&:model),
          dissent: dissent.map { |vote| { model: vote.model, reason: vote.reason } },
        )
        approved
      end

      private

      def vote(model, prompt:, candidate:, violation:)
        response = @agent.ask_once(vote_prompt(prompt, candidate, violation), model:, format: VOTE_SCHEMA, failover: false)
        parsed = parse_vote(response)
        Vote.new(model:, approved: parsed.fetch("approved", false), reason: parsed.fetch("reason", response.to_s[0, 240]))
      rescue StandardError => e
        Vote.new(model:, approved: false, reason: e.message.to_s[0, 240])
      end

      def vote_prompt(prompt, candidate, violation)
        <<~PROMPT
          Decide whether this candidate fix is safe to apply.
          Return JSON only: {"approved":true|false,"reason":"short reason"}

          Violation:
          rule=#{violation[:law]}
          severity=#{violation[:severity]}
          file=#{violation[:file]}
          line=#{violation[:line]}
          message=#{violation[:message]}

          Original fix prompt:
          #{prompt}

          Candidate fixed file:
          ```text
          #{candidate}
          ```
        PROMPT
      end

      def parse_vote(response)
        text = response.to_s.strip
        json = text[/\{.*\}/m] || "{}"
        data = JSON.parse(json)
        {
          "approved" => data["approved"] == true || data["approved"].to_s == "true",
          "reason" => data["reason"].to_s,
        }
      rescue JSON::ParserError
        # A vote that is not the JSON asked for approves nothing: "not approved" contains the word.
        { "approved" => false, "reason" => "unparseable vote: #{text[0, 220]}" }
      end
    end
  end
end
