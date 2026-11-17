# frozen_string_literal: true

module Master
  module Review
    class Agent
      # A bounded, source-backed research call for operator-requested /fix runs,
      # re-opening the class defined in review/agent.rb. Web tools screen
      # external text through the injection guard; returned text remains
      # evidence, not instructions, and repair validation stays local.
      #
      # The queries and URLs come from the research protocol in data, not from
      # a model, so the guarded web reads they need are approved for the call:
      # with no terminal the Governor refused every one ("non-TTY: cannot
      # prompt"), and with one it would stop an unattended run to ask per page.
      def research_sources(queries:, sources:, max_queries: 2, max_sources: 3, &progress)
        previous_protocol_read = Fiber[:master_protocol_read]
        Fiber[:master_protocol_read] = true
        records = []
        collect_search_records(records, Array(queries).first(max_queries.to_i.clamp(0, 5)), progress:)
        collect_fetch_records(records, Array(sources).first(max_sources.to_i.clamp(0, 6)), progress:)
        records
      ensure
        Fiber[:master_protocol_read] = previous_protocol_read
      end

      private

      def collect_search_records(records, queries, progress:)
        web = evidence_tool("WebSearch")
        queries.each_with_index do |query, index|
          collect_web_record(records, kind: "search", tool: web, tool_name: "WebSearch", label: query.to_s,
            index:, total: queries.size, progress:, call_args: { query: query.to_s },
            no_results_empty: true, text_limit: 1_300)
        end
      end

      def collect_fetch_records(records, sources, progress:)
        fetcher = evidence_tool("WebFetch")
        sources.each_with_index do |url, index|
          collect_web_record(records, kind: "fetch", tool: fetcher, tool_name: "WebFetch", label: url.to_s,
            index:, total: sources.size, progress:, call_args: { url: url.to_s },
            no_results_empty: false, text_limit: 1_500)
        end
      end

      def collect_web_record(records, kind:, tool:, tool_name:, label:, index:, total:, progress:, call_args:, no_results_empty:, text_limit:)
        progress&.call(event: "started", kind:, index: index + 1, total:, label:)
        begin
          result = tool&.call(**call_args)
          if result.respond_to?(:ok?) && result.ok?
            text = result.value!.to_s.strip
            status = text.empty? || (no_results_empty && text == "(no results)") ? "empty" : "ok"
            records << { "kind" => kind, "label" => label, "status" => status, "text" => text[0, text_limit] }
          else
            records << { "kind" => kind, "label" => label, "status" => "unavailable",
                         "text" => result.respond_to?(:message) ? result.message.to_s[0, 220] : "#{tool_name} unavailable" }
          end
        rescue StandardError => e
          records << { "kind" => kind, "label" => label, "status" => "unavailable", "text" => "#{e.class}: #{e.message.to_s[0, 200]}" }
        ensure
          progress&.call(event: "completed", kind:, index: index + 1, total:, label:,
                         status: records.last&.fetch("status", "unknown"))
        end
      end
    end
  end
end
