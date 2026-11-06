# frozen_string_literal: true

module Models
  # What registry/models.yml says about one model id: which lane answers it
  # and how that lane is reached. pub4 answered these questions in five places
  # (LaneSelection.kind, LaneQuota.lane_of, ModelRouter::Pool, the dispatcher's
  # *_model? predicates and ProviderCanary); here there is one reader.
  #
  # A lane is the unit that fails together: a subscription CLI
  # (claude-cli:..., grok-cli:...) or an HTTP provider (anthropic,
  # openrouter, ...). Kinds:
  #   :claude  `claude --print`, JSON result with usage and cost
  #   :cli     a signed-in CLI from cli_lanes (grok, codex) or agy
  #   :http    a provider core's LLM client speaks (protocol + base)
  # nil means no moved code reaches it (web-chat and ollama were not moved).
  class Catalog
    PREFIX = /\A(claude-cli|grok-cli|codex-cli|agy|web-chat|ollama):/
    # agy has no cli_lanes row in the registry; pub4 spelled its arguments in
    # cli_sender.rb, and they move here as the one place that knows them.
    AGY = { "binary" => "agy", "ask" => ["-p", "%{prompt}", "--output-format", "text"], "model_flag" => "--model" }.freeze

    attr_reader :models

    def initialize(models = Core::Registry.load(:models))
      @models = models
    end

    def lane_of(id)
      id = id.to_s
      id[PREFIX, 1] || provider_for(id) || "unknown"
    end

    # The HTTP provider whose model_pattern matches, in registry order.
    def provider_for(id)
      providers.find { |_name, row| row["model_pattern"] && id.to_s.match?(Regexp.new(row["model_pattern"])) }&.first
    end

    def kind(id)
      case lane_of(id)
      when "claude-cli" then :claude
      when "grok-cli", "codex-cli", "agy" then :cli
      else :http if (row = providers[lane_of(id)]) && row["protocol"]
      end
    end

    # The model name the lane is asked for: the id without its lane prefix.
    def model_name(id) = id.to_s.sub(PREFIX, "")

    def cli_lane(id)
      lane = lane_of(id)
      lane == "agy" ? AGY : @models.fetch("cli_lanes", {})[lane]
    end

    def provider(id) = providers.fetch(lane_of(id))

    def dead?(id) = @models.dig("lanes", "dead").to_a.include?(lane_of(id))

    def providers = @models.fetch("providers")

    # Ids in a tier, in the registry's order (the order is the curation).
    def tier(name) = @models.dig("tiers", name.to_s).to_a.map { |row| row.fetch("id") }

    def route(task) = @models.dig("routes", task.to_s) || @models.dig("routes", "fallback_default")

    def failover = @models.dig("failover", "sequence").to_a
  end
end
