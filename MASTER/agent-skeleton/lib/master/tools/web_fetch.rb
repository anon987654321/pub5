# frozen_string_literal: true

require "net/http"
require "uri"
require "nokogiri"

module Master
  module Tools
    # Fetch a URL and return readable text (HTML stripped).
    class WebFetch < Tool
      MAX_CHARS = 6000

      def name
        "web_fetch"
      end

      def description
        "Fetch an http(s) URL and return its readable text content (HTML tags stripped). " \
          "Use it to read pages found via web_search."
      end

      def parameters
        {
          type: "object",
          properties: {
            url: { type: "string", description: "Full http(s) URL to fetch" }
          },
          required: ["url"]
        }
      end

      def call(args)
        url = URI.parse(args.fetch("url"))
        unless url.is_a?(URI::HTTP)
          raise ArgumentError, "not an http(s) URL: #{url}"
        end

        body = get_with_redirects(url)
        text = Nokogiri::HTML(body).text.gsub(/\s+/, " ").strip
        { url: url.to_s, chars: text.length, text: text[0, MAX_CHARS].to_s }
      end

      private

      def get_with_redirects(uri, limit = 3)
        raise ArgumentError, "too many redirects" if limit.zero?

        response = Net::HTTP.get_response(uri)
        case response
        when Net::HTTPRedirection
          get_with_redirects(URI.join(uri, response["location"]), limit - 1)
        when Net::HTTPSuccess
          response.body
        else
          raise "HTTP #{response.code} for #{uri}"
        end
      end
    end
  end
end
