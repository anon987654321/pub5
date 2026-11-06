# frozen_string_literal: true

module Models
  # Which models to ask for a piece of text, best first. The text is
  # classified into a task, the task names a route, the route names a tier in
  # registry/models.yml, and failover.sequence's tiers follow it. A model no
  # moved lane reaches, a lane down by hand, or an HTTP provider without a key
  # never enters the chain; a lane in its cool-off stays in it, so the
  # dispatcher can say why it was passed over and the gate can wait for it.
  #
  # PUB5_MODEL pins one model and is the only lane: an operator who asked for
  # one model on every call had a quota-dead Opus hand /fix's repairs to
  # grok-cli mid-run, because pub4's strict switch was a second flag
  # (MASTER_MODEL_STRICT) the run had been started without. A pinned lane in
  # its cool-off is waited out (Gate), not dropped.
  class Router
    # Moved from pub4 ModelRouter::INTENT_PATTERNS and its chitchat regexes.
    INTENT_PATTERNS = {
      "code_generation" => /\b(implement|build|add|create|write|make|generate|scaffold|port|wire)\b/i,
      "refactoring" => /\b(refactor|rename|clean ?up|simplify|extract|inline|dedup|consolidate|tidy)\b/i,
      "architecture" => /\b(design|architect|structure|plan|approach|module|boundary|layer|topology)\b/i,
      "review" => /\b(review|critique|audit|check|council|tribunal|inspect|evaluate|judge)\b/i,
      "explanation" => /\b(explain|what is|how does|why does|describe|clarify|walk me through)\b/i
    }.freeze
    GREETING = /\A(?:hi|hello|hey|yo|sup|howdy|hei|hallo|good (?:morning|afternoon|evening))[!?.\s]*\z/i
    CASUAL = /\b(?:how are you|what'?s up|thanks|thank you|nice to meet|good night|takk)\b/i
    CASUAL_MAX = 120

    def initialize(catalog:, lanes:, knobs:)
      @catalog = catalog
      @lanes = lanes
      @knobs = knobs
    end

    def pin
      value = @knobs.fetch("PUB5_MODEL").to_s.strip
      value unless value.empty?
    end

    def classify(text)
      text = text.to_s.strip
      return "chitchat" if text.match?(GREETING) || (text.size <= CASUAL_MAX && text.match?(CASUAL))

      INTENT_PATTERNS.find { |_task, pattern| text.match?(pattern) }&.first || "exploration"
    end

    def chain(task)
      return [pin] if pin

      tiers = [@catalog.route(task), *@catalog.failover].compact.uniq
      tiers.flat_map { |tier| @catalog.tier(tier) }.uniq.select { |id| reachable?(id) }
    end

    # Reachable means some moved code can ask it now or after a wait: an HTTP
    # provider needs a key; a CLI lane is tried, and a missing binary stands
    # it down on the first call (Lanes::DEAD_S) rather than being probed here.
    def reachable?(id)
      kind = @catalog.kind(id) or return false
      return false if @catalog.dead?(id)
      return true unless kind == :http

      !@knobs.first(@catalog.provider(id).fetch("env")).nil?
    end
  end
end
