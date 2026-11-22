# frozen_string_literal: true

module Master
  module Review
    class Agent
      # The conversation turn, re-opening the class defined in review/agent.rb:
      # the chat door the face and the REPL call, its dispatch and finalization,
      # and the evidence preflight a research-shaped message routes through.
      # The single-shot doors and their failover stay in review/agent.rb, and
      # the guarded /fix research call lives in agent/research.rb.
      def chat(message, image: nil, stream: true, escalation_depth: 0, task_type: nil, &blk)
        compaction = prepare_chat_turn(message)
        return compaction if compaction.is_a?(Master::Result::Err)

        prepare_evidence(message) if prepare_evidence_for?(message, task_type)
        dispatch = prepare_chat_dispatch(message, task_type)
        if task_type.to_s == "nsfw" && dispatch[:selected_model].to_s != Io::LaneSelection.nsfw_model_id.to_s
          return Result.err(
            "NSFW lane unavailable. Set MASTER_NSFW=1 and MASTER_NSFW_MODEL to an installed local Ollama model; MASTER_NO_OLLAMA=1 remains a hard off.",
            category: :policy,
          )
        end

        rate_err = check_rate_limit(dispatch[:selected_model])
        return rate_err if rate_err

        response = dispatch_chat_response(dispatch, stream:, image:, &blk)
        return response if response.is_a?(Master::Result::Err)

        finalize_chat_response(response, message, dispatch:, image:, stream:, escalation_depth:, task_type:, &blk)
      rescue StandardError => chat_error
        record_trajectory!(message:, model: @config.model, outcome: "failed")
        Result.err("agent: #{chat_error.message}", category: :handler_exception)
      end

      def call(ctx)
        on_chunk = ctx[:on_chunk]
        task_type = ctx[:task_type]&.to_s
        image = ctx[:image] if ctx.respond_to?(:[]) && ctx.key?(:image)
        @felt_sense = ctx[:felt_sense]
        message = ctx[:message].to_s
        with_task_type(task_type) do
          if on_chunk
            chat(message, image:, stream: true, task_type:) { |chunk| on_chunk.call(chunk) }
          else
            chat(message, image:, task_type:)
          end
        end
      ensure
        @felt_sense = nil
        Fiber[:master_evidence_mode] = nil
        Fiber[:master_evidence_note] = nil
      end

      private

      def dispatch_chat_response(dispatch, stream:, image:, &blk)
        response = attempt_chat_with_fallbacks(candidate_models: dispatch[:candidate_models], prompt: dispatch[:prompt],
          context: dispatch[:context], stream:, image:, &blk)
        @deps.homeostat&.observe(response.is_a?(Master::Result::Err) ? :llm_failure : :llm_success)
        response
      end

      def finalize_chat_response(response, message, dispatch:, image:, stream:, escalation_depth:, task_type:, &blk)
        response = maybe_escalate(response, message, stream:, escalation_depth:, &blk)

        text = response.to_s
        recovery_result = handle_phantom_recovery(text, message:, image:, stream:, escalation_depth:, task_type:, &blk)
        return recovery_result if recovery_result

        @session.add_message(role: :assistant, content: text)
        answered = (response.model if response.respond_to?(:model)) || dispatch[:selected_model]
        record_trajectory!(message:, model: answered, outcome: "complete")
        publish_ctx_footer(answered)
        Result::Ok.new(text, answered)
      end

      # A hard compaction that failed leaves the window at 90% or more, and a
      # turn sent over it is cut off by the provider or silently truncated, so
      # the turn is refused with the compaction's error instead.
      def prepare_chat_turn(message)
        compaction = @context_window&.check_and_compact!
        return compaction if compaction.is_a?(Master::Result::Err)

        @tools.each { |t| t.reset! if t.respond_to?(:reset!) }
        Fiber[:master_tool_streak] = nil
        Fiber[:master_tree_seen] = nil
        Fiber[:master_trajectory_events] = []
        @memory&.auto_save(message) if @memory&.respond_to?(:auto_save)
        @session.add_message(role: :user, content: message)
        observe_preference_feedback(message)
      end

      # Observation is a bounded, opt-in post-ingest hook. A broken preference
      # store must not fail the conversation, and raw user text is never logged.
      def observe_preference_feedback(message)
        return if Fiber[:master_visitor] == true
        return unless defined?(Master::Device::OwnerPreferences)

        root = @config["root"] || Master::ROOT
        result = Master::Device::OwnerPreferences.observe_feedback(
          root:, subject: Fiber[:master_pair_subject], message:,
        )
        return unless result.is_a?(Hash) && result["status"] == "staged"

        @bus&.publish(
          "preferences:suggestion_staged",
          suggestion_id: result["suggestion_id"],
          evidence_count: result["count"],
        )
      rescue StandardError => e
        @bus&.publish("preferences:observation_unavailable", error: e.class.name)
        nil
      end

      # Plain chat stays lightweight, but an explicit request for current facts,
      # research, or a website still must receive its evidence route. The task_type
      # label describes presentation; it must not turn off browser selection.
      def prepare_evidence_for?(message, task_type)
        return false if task_type.to_s == "nsfw"
        return true unless task_type.to_s == "chat"

        !%i[conversation unknown].include?(Ground::EvidenceRouter.classify(message))
      end

      def prepare_evidence(message)
        mode = Ground::EvidenceRouter.classify(message)
        Fiber[:master_evidence_mode] = mode
        note = Ground::EvidenceRouter.prompt_for(mode)
        evidence = evidence_preflight(message, mode)
        Fiber[:master_evidence_note] = [note, evidence].compact.join("\n\n")
        @bus&.publish("evidence:routed", mode:, web_required: Ground::EvidenceRouter.web_required?(mode))
      end

      # A turn that needed the web and got nothing must not read as researched.
      LOOKUP_UNAVAILABLE = "Web lookup returned nothing this turn (no search tool, or no result). Say so plainly, " \
                           "answer from what you know if you can, and cite no source you did not read."

      def evidence_preflight(message, mode)
        if mode == :browser
          return unless message.to_s.match?(Ground::EvidenceRouter::SOCIAL_ACCOUNTS)

          return capability_preflight("social_browser", "status")
        end
        return capability_preflight("air_superiority", "scan") if mode == :device
        return if %i[repository conversation opinion].include?(mode)

        local = evidence_tool("SearchKnowledge")&.call(query: message.to_s)
        local_text = local.respond_to?(:ok?) && local.ok? ? local.value!.to_s : ""
        return "Local knowledge:\n#{local_text[0, 4_000]}" if mode == :unknown && !local_text.empty? && local_text != "(no results)"

        snippets = web_snippets(message, mode)
        return LOOKUP_UNAVAILABLE if snippets.empty? && Ground::EvidenceRouter.web_required?(mode)
        return if snippets.empty? && local_text.empty?

        parts = []
        parts << "Local knowledge:\n#{local_text[0, 3_000]}" unless local_text.empty?
        parts << "Web research:\n#{snippets.join("\n\n")[0, 6_000]}" unless snippets.empty?
        parts.join("\n\n")
      end

      # Deep research also asks for the official documentation. Direct references
      # to a research surface use its specialized adapter so the evidence arrives
      # in the shape that surface actually provides.
      def web_snippets(message, mode)
        text = message.to_s
        snippets = []

        if (source = specialized_web_source(text))
          result = source.call(**specialized_web_args(text))
          snippets << result.value!.to_s if result.respond_to?(:ok?) && result.ok?
        end

        web = evidence_tool("WebSearch")
        # External searches need the question's evidence topic, not the intimate
        # details that motivated it. The router leaves technical research intact.
        query = Ground::EvidenceRouter.web_search_query(text)
        searches = [query]
        searches << "#{query} official documentation" if mode == :deep_research
        snippets.concat(
          searches.filter_map do |query|
            result = web&.call(query:)
            result.value!.to_s if result.respond_to?(:ok?) && result.ok?
          end,
        )
        snippets
      end

      def specialized_web_source(message)
        return evidence_tool("Lovdata") if message.match?(/\b(?:lovdata|LOV-\d{4}-\d{2}-\d+(?:-\d+)?|FOR-\d{4}-\d{2}-\d+(?:-\d+)?)\b/i) ||
          (message.match?(/§\s*\d/) && message.match?(/\b[\p{L}]+(?:loven|forskriften)\b/i))
        return evidence_tool("Linguist") if message.match?(/\b(?:etymology|etymological|word origin|linguistic(?:s)?|idiom|pragmatics|register|grammar of|meaning of the word|word usage)\b/i) &&
          message.match?(/["'\u201C][^"'\u201D]{1,120}["'\u201D]|\b(?:word|phrase)\s+[\p{L}\p{N}'-]{2,80}/i)
        return evidence_tool("CodePen") if message.match?(/codepen\.io|\bcodepen\b/i)
        return evidence_tool("Gist") if message.match?(/gist\.github\.com/i)
        return evidence_tool("YoutubeTranscript") if message.match?(%r{https?://(?:www\.)?youtube\.com/|https?://youtu\.be/})
        return evidence_tool("YoutubeTranscript") if message.match?(/\byoutube transcript\b/i) && message.match?(/\b[A-Za-z0-9_-]{11}\b/)
        return evidence_tool("ArxivResearch") if message.match?(/\b(?:arxiv|ar5iv|academic papers?|research papers?|literature review)\b/i)
        if message.match?(/\b(?:github repos?|github repositories|open[- ]source projects|repo(?:sitory)? mining|popular repositories|trending repositories|best (?:ruby )?(?:gems|libraries|frameworks)|find (?:a few )?(?:projects|repositories|libraries) on github)\b/i)
          return evidence_tool("GitHubRepoMiner")
        end
        nil
      end

      def specialized_web_args(message)
        case
        when message.match?(/\b(?:lovdata|LOV-\d{4}-\d{2}-\d+(?:-\d+)?|FOR-\d{4}-\d{2}-\d+(?:-\d+)?)\b/i)
          lovdata_args(message)
        when message.match?(/\b(?:etymology|etymological|word origin|linguistic(?:s)?|idiom|pragmatics|register|grammar of|meaning of the word|word usage)\b/i)
          linguist_args(message)
        when message.match?(%r{https://codepen\.io/})
          { mode: "inspect", url: message[%r{https://codepen\.io/[^\s)]+}], limit: 8 }
        when message.match?(%r{https://gist\.github\.com/})
          { url: message[%r{https://gist\.github\.com/[^\s)]+}], full: false }
        when message.match?(%r{https?://(?:www\.)?youtube\.com/|https?://youtu\.be/})
          youtube_url_args(message)
        when message.match?(/\byoutube transcript\b/i) && message.match?(/\b[A-Za-z0-9_-]{11}\b/)
          youtube_transcript_args(message)
        when message.match?(/\b(?:arxiv|ar5iv|academic papers?|research papers?|literature review)\b/i)
          { query: message, sort_by: "relevance", limit: 5 }
        when message.match?(/\b(?:github repos?|github repositories|open[- ]source projects|repo(?:sitory)? mining|popular repositories|trending repositories|best (?:ruby )?(?:gems|libraries|frameworks)|find (?:a few )?(?:projects|repositories|libraries) on github)\b/i)
          github_repo_args(message)
        else
          { mode: "trending", limit: 8 }
        end
      end

      def lovdata_args(message)
        reference = message[%r{https://(?:www\.)?lovdata\.no/dokument/NL/(?:lov|forskrift)/[^\s)]+}] ||
                    message[/\b(?:LOV|FOR)-\d{4}-\d{2}-\d+(?:-\d+)?\b/i] || message
        { reference:, action: message.match?(/\b(?:search|find|which|hvilken|søk|finn)\b/i) ? "search" : "lookup",
          section: message[/§\s*([0-9]+[a-z]?(?:-[0-9]+[a-z]?)?)/i, 1] }
      end

      def linguist_args(message)
        language = message.match?(/\b(?:nynorsk|nn)\b/i) ? "nn" : (message.match?(/\b(?:bokmål|norwegian|norsk|nb)\b/i) ? "nb" : (message.match?(/\benglish|en\b/i) ? "en" : "auto"))
        focus =
          case
          when message.match?(/\b(?:etymology|etymological|word origin)\b/i) then "etymology"
          when message.match?(/\bidiom\b/i) then "idiom"
          when message.match?(/\bgrammar\b/i) then "grammar"
          when message.match?(/\bregister\b|\bformal|informal|colloquial\b/i) then "register"
          when message.match?(/\bpragmatics\b|\bwhat (?:does|did) .* mean\b/i) then "pragmatics"
          when message.match?(/\busage\b/i) then "usage"
          else "meaning"
          end
        quoted = message.match(/["'\u201C]([^"'\u201D]{1,120})["'\u201D]/)&.captures&.first
        unquoted = message.match(/\b(?:word|phrase)\s+([\p{L}\p{N}'-]{2,80})/i)&.captures&.first
        { term: quoted || unquoted.to_s, language:, focus:, limit: 4 }
      end

      def youtube_url_args(message)
        url = message[%r{https?://(?:www\.)?youtube\.com/[^\s)]+|https?://youtu\.be/[^\s)]+}]
        { url:, timestamps: message.match?(/\b(?:timestamps?|timed notes)\b/i) }
      end

      def youtube_transcript_args(message)
        { url: message[/\b[A-Za-z0-9_-]{11}\b/], timestamps: message.match?(/\b(?:timestamps?|timed notes)\b/i) }
      end

      def github_repo_args(message)
        { query: message, sort: message.match?(/\b(?:recent|latest|updated|active)\b/i) ? "updated" : "stars", limit: 5 }
      end

      def capability_preflight(plugin, action)
        tool = evidence_tool("PluginObserve")
        return unless tool

        result = tool.call(plugin:, action:, args: {})
        return unless result.respond_to?(:ok?) && result.ok?

        value = result.value!.to_s
        "Capability observation (#{plugin}/#{action}):\n#{value[0, 6_000]}"
      rescue StandardError => e
        "Capability observation unavailable: #{e.message}"
      end

      def evidence_tool(name)
        @tools.find { |tool| tool.class.name.to_s.split("::").last == name }
      end

      def publish_ctx_footer(model_id)
        est = @session.respond_to?(:token_est) ? @session.token_est : 0
        limit = Master.context_window(model_id)
        pct = limit.positive? ? ((est.to_f / limit) * 100).round(1) : 0
        @bus&.publish("ctx:footer", model: model_id, token_est: est, limit:, pct:)
      end

      def prepare_chat_dispatch(message, task_type)
        candidate_models = routed_models(message, task_type:)
        selected_model = candidate_models.first
        @bus&.publish("llm:routed", model: selected_model, task_type: task_type || @config.task_type, reason: "routing")
        prompt = topic_anchored(message)
        context = conversation_context
        tokens_approx = Trace::Session.estimate_tokens(message)
        @bus&.publish("llm:request", model: selected_model, tokens: tokens_approx)
        if ENV["MASTER_LLM_RECORD"] == "1"
          Fiber[:master_trajectory_events] << { "event" => "llm:request", "model" => selected_model, "tokens" => tokens_approx }
        end
        @deps.homeostat&.observe(:llm_call)
        { candidate_models:, selected_model:, prompt:, context: }
      end

      def handle_phantom_recovery(text, message:, image:, stream:, escalation_depth:, task_type:, &blk)
        recovery = Master::PhantomRecovery.handle(text, bus: @bus, session: @session)
        case recovery[:action]
        when :discard
          Result.err("phantom recovery: discarded repetitive response", category: :policy)
        when :escalate
          chat(message, image:, stream:, escalation_depth: escalation_depth + 1, task_type:, &blk) if escalation_depth < 2
        when :halt
          Result.err("phantom recovery: halted after repeated phantom patterns", category: :policy)
        end
      end

      # The ensure belongs to the swap alone: on the early return it wrote nil over
      # the configured task type.
      def with_task_type(type)
        return yield unless type && !type.empty?

        old = @config["task_type"]
        begin
          @config["task_type"] = type
          yield
        ensure
          @config["task_type"] = old
        end
      end
    end
  end
end
