# frozen_string_literal: true

require "yaml"
require "socket"
require_relative "lane_quota"
require_relative "lane_health"
require_relative "lane_state"

module Master
  module Io
    # The one rule for choosing a model, for /fix and the council alike: take
    # the models of the requested tier in the order data/models.yml lists them,
    # drop the dead lanes (quota spent, unreachable, silent, or on the hand-kept
    # dead list), and use the first that is left. A failure falls to the next
    # live one (Agent#retry_on_broke_lane walks the same order).
    #
    # After the live subscription and direct-API lanes come the cheap paid models
    # of the capped tail (Io::PaidTail), then the local Ollama models (the
    # always-online floor), then the free models: an unmetered model is a floor to
    # stand on, never a lane to prefer, and a free nemotron call cost 150 to 190
    # seconds against seconds on a live subscription CLI. Among the free ones the
    # fastest recently-answering goes first; an unmeasured one is assumed neutral.
    # A call that carries an image tries the vision-capable lanes first.
    #
    # The council spreads its personas over the live providers with `spread`,
    # so one dead lane never decides what the whole panel sounds like.
    module LaneSelection
      extend self

      MODELS = File.expand_path("../../data/models.yml", __dir__)
      CLI_BINARIES = { "claude-cli" => "claude", "grok-cli" => "grok", "llama-cli" => "llama-cli" }.freeze
      KIND_RANK = { remote: 0, paid_tail: 1, local: 2, free: 3 }.freeze
      FREE_CLASS_KINDS = %i[free local].freeze
      # Where a suspended floor rides in the selection sort: the same rank
      # ModelRouter#fallback_rank hands it, so the per-call chain and the
      # selection order agree that every answering class goes first.
      FLOOR_SUSPENDED_RANK = 9
      FLOOR_LOCK = Mutex.new
      NOT_SUBSCRIPTION = 10_000
      NEUTRAL_LATENCY_S = 45
      UNMEASURED_TIMEOUT_S = 60
      SLOW_S = 600
      CATALOGUE_TIERS = %w[default strong local].freeze

      # The lane a model id travels: the text before ":" for CLI lanes, else the
      # vendor slug of an API id.
      def provider(model)
        id = model.to_s
        return id.split(":", 2).first(2).join(":") if id.start_with?("web-chat:")

        colon = id.index(":")
        slash = id.index("/")
        return id[0...colon].to_s if colon && (!slash || colon < slash)
        return id.split("/", 2).first.to_s if slash

        id.split(/[:-]/).first.to_s
      end

      def kind(model, cfg: config)
        id = model.to_s
        return :paid_tail if Io::PaidTail.member?(id)
        return :free if id.end_with?(":free", ":cloud", "-cloud") || id.start_with?("web-chat:")
        return :local if LaneHealth.local_model?(id)
        return :free if keyless_slug?(id, cfg)

        :remote
      end

      # HostedEndpoints already applies each provider's keyless rule to its
      # live /models listing (tier, isFree or allow). Classify from that exact
      # filtered index rather than maintaining a second, weaker copy of those
      # provider-specific rules here.
      def keyless_slug?(id, cfg)
        lane = cfg.dig("openai_compatible", provider(id))
        return false unless lane.is_a?(Hash) && lane["keyless"].is_a?(Hash)

        endpoint = hosted_endpoint_for(id, cfg:)
        endpoint && endpoint[:key].nil?
      end

      # Live models, remote before local before free, each group in the order given.
      # Ollama is removed before ranking unless its config or explicit opt-in enables
      # it; even the all-dead fallback may not resurrect a disabled local lane.
      # `free_last: false` keeps the given order for routes that choose free on purpose.
      # `latency` answers seconds for a model or nil when it was never measured.
      # `vision: true` puts the lanes that read images ahead of those that do not.
      def ollama_model?(model) = model.to_s.start_with?("ollama:", "ollama/")

      # The local CLI is usable only when its explicitly configured GGUF file is
      # present. A binary alone is not a model, and discovery never downloads one.
      def local_cli_model_available?(model)
        lane = config.dig("cli_lanes", provider(model))
        env_name = lane && lane["model_path_env"].to_s
        return true if env_name.to_s.empty?

        path = ENV[env_name].to_s
        !path.empty? && File.file?(path) && File.readable?(path)
      end

      # One policy for routing, inventory and boot selection. The file is the
      # default; an environment opt-in is deliberately explicit and reversible.
      def ollama_enabled?(cfg: config)
        return false if ENV["MASTER_NO_OLLAMA"] == "1"
        return true if ENV["MASTER_OLLAMA_ENABLED"] == "1"

        cfg.dig("ollama", "enabled") == true || zero_key_probe?(cfg)
      end

      # Zero-key boot: with no remote key configured anywhere, a reachable
      # local brain is the quiet default instead of a dead lane. The data file
      # arms it with `probe: true`; MASTER_NO_OLLAMA=1 refuses it outright and
      # an explicit `enabled: true` needs no probe. Ranking asks this often,
      # so the socket verdict is held for a minute rather than per call.
      def zero_key_probe?(cfg)
        CONFIG_LOCK.synchronize do
          held = @zero_key_probe
          return held[1] if held && Time.now.to_i - held[0] < 60

          verdict = cfg.dig("ollama", "probe") == true &&
                    !Master.any_api_key_present? && api_listening?(cfg)
          @zero_key_probe = [Time.now.to_i, verdict]
          verdict
        end
      end

      def api_listening?(cfg)
        return false unless (base = cfg.dig("ollama", "default_base_url"))

        addr = URI(base)
        TCPSocket.new(addr.host || "localhost", addr.port || 11434).close
        true
      rescue SystemCallError, IOError, SocketError, URI::InvalidURIError
        false
      end

      def order(models, free_last: true, latency: nil, vision: false, manual: LaneQuota.manual_dead, lead: [],
                cfg: config)
        live = Array(models).map(&:to_s).reject(&:empty?).uniq
        live.reject! { |id| ollama_model?(id) && !ollama_enabled?(cfg:) }
        live = live.reject { |id| LaneQuota.dead?(id, manual:) || !LaneState.usable?(id) }
        live = live.reject { |id| kind(id) == :paid_tail && !Io::PaidTail.enabled? }
        unless free_last
          return live unless vision

          return vision_rank_order(live, cfg:) + live.reject { |id| vision?(id) }
        end

        ranked = rank_pool(live, latency:, lead:, cfg:)
        return ranked unless vision

        vision_rank_order(ranked, cfg:) + ranked.reject { |id| vision?(id) }
      end

      # The selection sort without the liveness filter. `order` answers [] when
      # every candidate reads dead, and the all-dead fallback then returns the
      # list as given - which is how a walk burned its queue on dead :free
      # slugs in file order while a ranked live lane sat further back
      # (2026-11-07). The refusal order goes through the same sort, so a walk
      # that must try something, or name why it cannot, does it in the order
      # the class ranks and the suspended floor decide.
      def ranked_order(models, free_last: true, latency: nil, vision: false, lead: [], cfg: config)
        candidates = Array(models).map(&:to_s).reject(&:empty?).uniq
        unless free_last
          return candidates unless vision

          return vision_rank_order(candidates, cfg:) + candidates.reject { |id| vision?(id) }
        end

        ranked = rank_pool(candidates, latency:, lead:, cfg:)
        return ranked unless vision

        vision_rank_order(ranked, cfg:) + ranked.reject { |id| vision?(id) }
      end

      # The class a lane rides at in the selection sort. A floor the run
      # suspended drops to FLOOR_SUSPENDED_RANK: free and local stay in the
      # list - never-modelless keeps them as the last resort - but every class
      # that answers goes first. A route that asks for free on purpose passes
      # free_last: false and never reaches this sort.
      def class_rank(id)
        rank = KIND_RANK.fetch(kind(id))
        return rank unless free_floor_suspended? && FREE_CLASS_KINDS.include?(kind(id))

        FLOOR_SUSPENDED_RANK
      end

      def rank_pool(ids, latency:, lead:, cfg:)
        preferred = Array(lead).map(&:to_s).reject(&:empty?).uniq
        preferred_rank = preferred.each_with_index.to_h
        listed = (preferred + catalogue(cfg:)).uniq
        ids.each_with_index.sort_by do |id, index|
          within_class = preferred_rank.fetch(id, preferred.length + subscription_rank(id, listed))
          [class_rank(id), within_class, free_latency(id, latency), index]
        end.map(&:first)
      end

      def subscription_lanes = Array(config.fetch("subscription_lanes"))

      def subscription?(model) = subscription_lanes.include?(LaneQuota.lane_of(model))

      # Low for a subscription lane (its lane position, then its place in the
      # catalogue so opus precedes sonnet as data/models.yml lists them), high
      # for every other model, which keeps the order it arrived in.
      def subscription_rank(id, listed)
        return NOT_SUBSCRIPTION unless kind(id) == :remote && subscription?(id)

        subscription_lanes.index(LaneQuota.lane_of(id)) * 100 + (listed.index(id) || 99)
      end

      # The same ids with the live subscription lanes first, in their fixed order;
      # every other id keeps its place. The pool's measured utility ranks within
      # a class, never across it.
      def subscriptions_first(ids, lead: [])
        listed = (Array(lead) + catalogue).uniq
        Array(ids).each_with_index.sort_by { |id, index| [subscription_rank(id, listed), index] }.map(&:first)
      end

      # The ids of the tier the rules route this task type to, in the order
      # data/models.yml lists them: the lane order the route asks for, so a route
      # to the fast tier leads with sonnet where the default tier leads with opus.
      def route_lead(rules, task_type)
        tier = rules.dig("routes", task_type.to_s)
        Array(rules.dig("models", tier)).filter_map { |row| row["id"] if row.is_a?(Hash) }
      end

      # A free lane's rank latency: the measured catalog reading first, then
      # the caller's latency probe, then the neutral constant. The catalog
      # carries the field as free_latency_s, recorded by the runtime that made
      # the call, so ranking survives a new process.
      def free_latency(id, latency)
        return 0.0 unless kind(id) == :free

        measured = catalog_free_latency(id)
        return measured if measured

        (latency&.call(id) || free_tier.fetch("neutral_latency_s", NEUTRAL_LATENCY_S)).to_f
      end

      def catalog_free_latency(id)
        @catalog_latencies ||= {}
        return @catalog_latencies[id] if @catalog_latencies.key?(id)

        require_relative "catalog_index"
        db = Master::Io::CatalogIndex::DEFAULT_DB
        @catalog_latencies[id] = File.file?(db) ? Master::Io::CatalogIndex.new(db_path: db).free_latency_s(id) : nil
      rescue StandardError
        @catalog_latencies[id] = nil
      end

      def free_tier = config.fetch("free_tier", {})

      def unmeasured_timeout_s = Integer(free_tier.fetch("unmeasured_timeout_s", UNMEASURED_TIMEOUT_S))

      # Bound every completion, not only an unmeasured lane: a short health probe says little about a repair prompt.
      def free_call_timeout_s
        value = Integer(free_tier.fetch("call_timeout_s", UNMEASURED_TIMEOUT_S), exception: false)
        value&.positive? ? value : UNMEASURED_TIMEOUT_S
      end

      # Whether a lane reads images: the catalog row's input modalities when it has one, else the vision families.
      def vision?(model)
        id = model.to_s
        row = catalog_modalities(id)
        return row.include?("image") if row

        !vision_family("blind").match?(id) && vision_family("reads_images").match?(id)
      end

      # Human-preference ranking only applies after image capability is known.
      # It cannot make a text-only model eligible for image-bearing work.
      def vision_rank_order(models, cfg: config)
        patterns = Array(cfg.dig("vision_families", "review_rank"))
        Array(models).map(&:to_s).reject(&:empty?).uniq.select { |id| vision?(id) }
          .each_with_index.sort_by do |id, index|
            [vision_review_rank(id, patterns), class_rank(id), index]
          end.map(&:first)
      end

      def vision_review_rank(id, patterns)
        patterns.each_with_index do |pattern, index|
          return index if Regexp.new(pattern, Regexp::IGNORECASE).match?(id)
        end
        patterns.length
      rescue RegexpError => e
        Master::Ground::Swallow.log(e, context: "LaneSelection.vision_review_rank", model: id)
        patterns.length
      end

      def vision_family(key) = Regexp.new(config.fetch("vision_families").fetch(key).join("|"), Regexp::IGNORECASE)

      def catalog_modalities(id)
        @modalities ||= begin
          require_relative "catalog_index"
          db = Master::Io::CatalogIndex::DEFAULT_DB
          File.file?(db) ? Master::Io::CatalogIndex.new(db_path: db).search(nil, source: "openrouter", limit: 5_000).to_h { |r| [r["id"], r["input_modalities"].to_s.split(",").map(&:strip)] } : {}
        rescue StandardError
          {}
        end
        @modalities[id]
      end

      # Every id models.yml names in any tier.
      def explicit_models(cfg: config)
        cfg.fetch("models", {}).values.flatten.filter_map { |row| row["id"] if row.is_a?(Hash) }.uniq
      end

      # The first live model of the list, or nil when every lane is dead.
      def first_live(models) = order(models).first

      # `order`, except that when every model is dead the list comes back in
      # ranked_order, so the dispatcher can refuse it with the typed Offline
      # that says why - and a walk that tries anyway does it in ranked order.
      def order_or_all(models, free_last: true, cfg: config, **rest)
        candidates = Array(models).map(&:to_s).reject(&:empty?).uniq
        candidates.reject! { |id| ollama_model?(id) && !ollama_enabled?(cfg:) }
        live = order(candidates, free_last:, cfg:, **rest)
        live.empty? ? ranked_order(candidates, free_last:, **rest) : live
      end

      # The live models of the best class that has any: a pool may rank them by
      # measured utility, but never trades a live subscription for a free model.
      # All dead: the list as given, for the dispatcher to refuse with the typed Offline.
      def best_class(models, free_last: true, **rest)
        live = order_or_all(models, free_last:, **rest)
        return live unless free_last

        live.select { |id| kind(id) == kind(live.first) }
      end

      # One model per key, drawn from the best class that has a live lane and
      # spread across its distinct providers; a single provider is reused.
      def spread(keys, models, vision: false)
        live = order(models, vision:)
        sighted = live.select { |id| vision?(id) }
        live = sighted if vision && sighted.any?
        best = live.select { |id| kind(id) == kind(live.first) }
        flat_rate = best.select { |id| subscription?(id) }
        reps = (flat_rate.empty? ? best : flat_rate).group_by { |id| provider(id) }.values.map(&:first)
        Array(keys).each_with_index.to_h { |key, index| [key, reps.empty? ? nil : reps.fetch(index % reps.size)] }
      end

      CONFIG_LOCK = Mutex.new

      # Read straight from the file: `operator fix status` asks without booting the runtime. Parsed once per
      # change of the file and handed out frozen: a chat turn ranked its lanes three times, and parsing this
      # file on each of the hundreds of calls that made took 1.4s a turn.
      def config(path = MODELS)
        return {} unless File.file?(path)

        stat = File.stat(path)
        key = [path, stat.mtime.to_r, stat.size]
        remember_config(key, path) unless cached_config(key)
        cached_config(key)
      end

      def cached_config(key) = CONFIG_LOCK.synchronize { @config_cache.last if @config_cache&.first == key }

      def remember_config(key, path)
        parsed = deep_freeze(YAML.safe_load_file(path, aliases: true) || {})
        CONFIG_LOCK.synchronize { @config_cache = [key, parsed] }
      end

      def deep_freeze(value)
        case value
        when Hash then value.each { |key, item| deep_freeze(key) && deep_freeze(item) }
        when Array then value.each { |item| deep_freeze(item) }
        end
        value.freeze
      end

      # The models of a tier as data/models.yml lists them.
      def tier(name, cfg: config)
        Array(cfg.dig("models", name.to_s)).filter_map { |row| row["id"] if row.is_a?(Hash) }
      end

      # HostedEndpoints owns live model discovery and provider-specific keyless
      # filtering. Reuse one resolver for this process; /model refresh invalidates it.
      def hosted_resolver(root: Master::ROOT)
        return @hosted_resolver if root.to_s == Master::ROOT.to_s && @hosted_resolver

        require_relative "../cli/routing/model_router"
        resolver = Master::CLI::Routing::ModelRouter.hosted_resolver(root:)
        @hosted_resolver = resolver if root.to_s == Master::ROOT.to_s
        resolver
      end

      def reset_hosted_resolver! = (@hosted_resolver = nil)

      def hosted_models(cfg: config)
        return [] unless cfg.equal?(config)

        Array(hosted_resolver.hosted_models)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LaneSelection.hosted_models")
        []
      end

      def hosted_endpoint_for(model, cfg: config)
        return unless cfg.equal?(config)

        hosted_resolver.hosted_endpoint_for(model)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LaneSelection.hosted_endpoint_for", model:)
        nil
      end

      def hosted_provider?(model, cfg: config)
        cfg.dig("openai_compatible", provider(model)).is_a?(Hash)
      end

      # Every model in the declared tiers plus every currently listed hosted
      # model the same runtime dispatcher can reach.
      def catalogue(cfg: config)
        ids = CATALOGUE_TIERS.flat_map { |name| tier(name, cfg:) }
        ids.concat(hosted_models(cfg:)) if cfg.equal?(config)
        ids.uniq
      end

      # The tier's live models whose lane can answer on this machine, in selection order.
      def pool(name = "default", cfg: config, alive: method(:alive?))
        order(tier(name, cfg:), cfg:).select { |id| alive.call(id) }
      end

      def alive?(model)
        id = model.to_s
        return false if ollama_model?(id) && !ollama_enabled?
        return false if Master::Io::ModelQuota.over_quota?(id)

        binary = CLI_BINARIES[LaneQuota.lane_of(id)]
        if binary
          return false if ENV["MASTER_NO_#{binary.upcase}_CLI"] == "1"

          return on_path?(binary) && local_cli_model_available?(id)
        end
        return Master.agy_cli_available? if provider(id) == "agy"
        return ollama_alive?(id) if id.start_with?("ollama:")
        return !hosted_endpoint_for(id).nil? if hosted_provider?(id)

        key_present_for?(id)
      end

      # providers.yml model_pattern and env; any key answers for an unnamed vendor.
      def api_keys = Master.provider_config(root: Master::ROOT).values.grep(Hash).select { |row| row["model_pattern"] }
                           .map { |row| [Regexp.new(row["model_pattern"]), Array(row["env"])] }

      def key_present_for?(id)
        # The user-owned gateway is the key boundary itself: the URL is the opt-in and its key is optional.
        # A `gateway:` id now also sits in the declared tiers, so the answer is the URL's presence,
        # never the generic any-key floor below (which would call it alive on a machine with an
        # unrelated provider key and no gateway configured).
        return !ENV["MASTER_LLM_GATEWAY_URL"].to_s.strip.empty? if id.start_with?("gateway:")

        _pattern, envs = api_keys.find { |pattern, _envs| pattern.match?(id) }
        envs ? envs.any? { |env| Master.api_key_present?(env) } : Master.any_api_key_present?
      end

      # A local model needs the daemon, which this starts once when it is down.
      def ollama_alive?(id)
        return false unless ollama_enabled?
        return false if LaneQuota.dead?(id)

        %i[up started].include?(LaneHealth.ensure_ollama.state)
      end

      def on_path?(binary) = !Master::Io::Exec.cli_binary(binary).nil?

      # "online: yes via X" or "online: NO (all lanes dead) ..." over the catalogue.
      def online_line(cfg: config)
        LaneHealth.line(catalogue(cfg:), refuses: ->(m) { LaneQuota.dead?(m) || !alive?(m) })
      end

      # The models that can answer now, in selection order: the catalogue minus
      # the dead (quota, health, hand-kept list) and the lanes this machine lacks.
      def live_lanes(cfg: config, alive: method(:alive?)) = order(catalogue(cfg:)).lazy.select { |id| alive.call(id) }

      # The lane a run starts on and why. Availability decides; a saved model is
      # a preference, honoured only while it is live and no worse a class than
      # the best live lane, and MASTER_MODEL alone forces a lane.
      def boot_choice(env: ENV, saved: nil, cfg: config, alive: method(:alive?))
        forced = env["MASTER_MODEL"].to_s.strip
        return [forced, "MASTER_MODEL"] unless forced.empty?

        live = live_lanes(cfg:, alive:)
        return [saved.to_s, "saved preference"] if preference_leads?(saved, live)

        [live.first, "availability"]
      end

      def preference_leads?(model, live)
        id = model.to_s
        return false if id.empty? || !live.include?(id)

        no_worse_class?(id, live.first)
      end

      # A model of the same class as the head, or better: a free preference never
      # leads a live subscription.
      def no_worse_class?(model, head)
        KIND_RANK.fetch(kind(model)) <= KIND_RANK.fetch(kind(head))
      end

      # /fix turns the guard on: a free or local lane asked for a model call
      # while a subscription or API lane is live is the defect that spent hours
      # on a free model. One warning per lane.
      def watch_free_class!(on = true)
        FLOOR_LOCK.synchronize do
          @watching = on
          @warned = {}
          @floor_suspended = false
          @floor_dead_count = 0
          @floor_notice = nil
          @successful_live_saviors = {}
        end
      end

      # The free floor proved dead after consecutive zero-success outcomes
      # (RunPulse promotes after three). A suspended floor stops winning the
      # per-call chain rankings: the free class is a floor to stand on, and a
      # floor that answers nothing is not a floor to stand on. The state lands
      # immediately; the one-word line waits for announce_free_floor_suspension,
      # so nobody ever has to emit a trace line from inside an event handler
      # or another lock's footprint.
      def suspend_free_floor!(live = nil)
        id = live.to_s
        return if id.empty? || !LaneState.usable?(id)

        FLOOR_LOCK.synchronize do
          return if @floor_suspended
          return unless @successful_live_saviors&.key?(id)

          @floor_suspended = true
          @floor_notice = "free floor suspended for this run: #{id} takes the work while it answers"
          true
        end
      end

      # Exactly one status line, printed by whichever ticker thread asks first.
      def announce_free_floor_suspension
        notice = FLOOR_LOCK.synchronize { @floor_notice }
        return unless notice

        Master::Trace::Dmesg.status("fix0", notice)
      ensure
        FLOOR_LOCK.synchronize { @floor_notice = nil }
      end

      def free_floor_suspended? = FLOOR_LOCK.synchronize { @floor_suspended == true }

      FLOOR_DEAD_LIMIT = 3

      # A candidate becomes the free floor's replacement only after a real
      # completion in this watched run. Availability alone is not proof.
      def note_provider_outcome(model, status, cfg: config, alive: method(:alive?))
        id = model.to_s
        result = status.to_sym
        free = FREE_CLASS_KINDS.include?(kind(id))

        dead_count, suspended = FLOOR_LOCK.synchronize do
          @successful_live_saviors ||= {}
          if result == :success
            if free
              @floor_dead_count = 0
            else
              @successful_live_saviors[id] = true
            end
          elsif free
            @floor_dead_count = (@floor_dead_count || 0) + 1
          else
            @successful_live_saviors.delete(id)
          end
          [@floor_dead_count.to_i, @floor_suspended == true]
        end

        return if result == :success && free
        return if result != :success && !free
        return if dead_count < FLOOR_DEAD_LIMIT || suspended

        live = live_savior(cfg:, alive:)
        return unless live

        if suspend_free_floor!(live)
          announce_free_floor_suspension
        end
      rescue StandardError => e
        if ENV["MASTER_FLOOR_DEBUG"] == "1"
          Master::Trace::Dmesg.status("fix0", "floor debug: counter crashed #{e.class}: #{e.message}")
          raise if ENV["MASTER_FLOOR_DEBUG_STRICT"] == "1"
        end
        nil
      end

      # The free floor's replacement must be both usable by every refusal store
      # and proven by a successful provider completion in this run.
      def live_savior(cfg: config, alive: method(:alive?))
        successful = FLOOR_LOCK.synchronize { (@successful_live_saviors || {}).keys }
        live_lanes(cfg:, alive:).find do |candidate|
          successful.include?(candidate) &&
            !FREE_CLASS_KINDS.include?(kind(candidate)) &&
            LaneState.usable?(candidate)
        end
      end

      def free_class_warning(model, operation, cfg: config, alive: method(:alive?))
        id = model.to_s
        # A lane probe asks every lane on purpose; that is not work on a free lane.
        return unless @watching && FREE_CLASS_KINDS.include?(kind(id)) && operation != :lane_probe
        return if (@warned ||= {})[id]

        better = live_savior(cfg:, alive:)
        return unless better

        @warned[id] = true
        "WARNING free-class lane #{id} used for #{operation || "a model call"} while #{better} is live"
      rescue StandardError
        nil
      end

      def note_use(model, operation)
        text = free_class_warning(model, operation)
        Master::Trace::Dmesg.status("fix0", text) if text
      end

      # A MASTER_MODEL pin is the only lane; MASTER_MODEL_STRICT=0 lets it fail over.
      def strict_pin?(env = ENV) = env["MASTER_MODEL_STRICT"].to_s != "0"

      def pin_label(env = ENV)
        strict_pin?(env) ? "pinned (MASTER_MODEL), no failover" : "pinned (MASTER_MODEL), failover on"
      end

      # What /model and fix status print: the effective #1 lane and why.
      def primary_report(env: ENV, saved: nil, cfg: config, alive: method(:alive?))
        lane, source = boot_choice(env:, saved:, cfg:, alive:)
        return "primary: no live lane (every catalogue lane is dead or absent)" if lane.to_s.empty?

        why = {
          "MASTER_MODEL" => pin_label(env),
          "saved preference" => "saved preference, live",
          "availability" => "first live lane by availability " \
                            "(#{subscription_lanes.join(" > ")}, then APIs, paid tail, local, free)",
        }.fetch(source)
        dead = catalogue(cfg:).select { |id| LaneQuota.dead?(id) }.map { |id| LaneQuota.lane_of(id) }.uniq
        "primary: #{lane} (#{why}#{dead.empty? ? "" : "; dead: #{dead.join(", ")}"})"
      end

      # What /fix prints once at its start: the live pool in selection order.
      def announce(cfg: config, alive: method(:alive?))
        Master::Trace::Dmesg.status("lane0", online_line(cfg:))
        live = live_lanes(cfg:, alive:).to_a
        Master::Trace::Dmesg.status("lane0", "selection order: #{live.empty? ? "none live" : live.first(6).join(" > ")}")
        live
      rescue StandardError
        nil
      end
    end
  end
end
