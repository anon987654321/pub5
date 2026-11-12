# frozen_string_literal: true

require "faraday"

module Master
  module Tools
    # Web search via the Brave Search API (https://brave.com/search/api/).
    # Set MASTER_BRAVE_API_KEY to enable. Swap the #call body for
    # Serper / Tavily / a self-hosted SearXNG — the tool interface stays identical.
    class WebSearch < Tool
      ENDPOINT = "https://api.search.brave.com/res/v1/web/search"

      def name
        "web_search"
      end

      def description
        "Search the web and return the top results (title, url, snippet)."
      end

      def parameters
        {
          type: "object",
          properties: {
            query: { type: "string", description: "Search query" },
            count: { type: "integer", description: "Number of results (1-10)" }
          },
          required: ["query"]
        }
      end

      def call(args)
        key = ENV["MASTER_BRAVE_API_KEY"]
        return { error: "set MASTER_BRAVE_API_KEY to enable web_search" } unless key

        count = args.fetch("count", 5).to_i.clamp(1, 10)

        conn = Faraday.new(url: ENDPOINT) do |f|
          f.options.timeout = 15
          f.options.open_timeout = 5
          f.response :json
          f.adapter :net_http
        end

        resp = conn.get do |req|
          req.params["q"] = args.fetch("query")
          req.params["count"] = count
          req.headers["Accept"] = "application/json"
          req.headers["X-Subscription-Token"] = key
        end

        raise "HTTP #{resp.status} from search provider" unless resp.status == 200

        results = resp.body.dig("web", "results") || []
        results.first(count).map do |r|
          { title: r["title"], url: r["url"], snippet: r["description"] }
        end
      end
    end
  end
end
