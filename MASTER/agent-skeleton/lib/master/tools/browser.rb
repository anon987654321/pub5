# frozen_string_literal: true

require "nokogiri"

begin
  require "ferrum"
rescue LoadError
  nil # optional dependency; #call degrades gracefully when missing
end

module Master
  module Tools
    # Render a page in a real (headless) Chromium via ferrum: JavaScript is
    # executed, so it works on pages web_fetch cannot read. Needs
    # `gem "ferrum"` plus Chromium installed on the host.
    class Browser < Tool
      def name
        "browser"
      end

      def description
        "Open a URL in a headless browser (JavaScript executed) and return the rendered " \
          "page text; optionally save a screenshot. Use when web_fetch returns empty or " \
          "scripted content."
      end

      def parameters
        {
          type: "object",
          properties: {
            url: { type: "string", description: "Full http(s) URL to open" },
            screenshot_path: { type: "string", description: "Optional path to save a PNG screenshot" }
          },
          required: ["url"]
        }
      end

      def call(args)
        unless defined?(Ferrum)
          return { error: "ferrum not installed; add `gem \"ferrum\"` and install Chromium" }
        end

        url = args.fetch("url")
        browser = Ferrum::Browser.new(timeout: 25, window_size: [1280, 1024])
        begin
          browser.goto(url)
          html = browser.body
          text = Nokogiri::HTML(html).text.gsub(/\s+/, " ").strip[0, 6000].to_s

          result = { url: url, chars: text.length, text: text }
          if (path = args["screenshot_path"])
            browser.screenshot(path: path)
            result[:screenshot] = path
          end
          result
        ensure
          browser.quit
        end
      end
    end
  end
end
