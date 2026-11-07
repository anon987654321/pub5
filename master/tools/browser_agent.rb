# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "uri"

module Master
  module Tools
    # Read-only Ferrum browser. A session is bound to one public HTTPS host
    # and one resolved IPv4 address. Only same-host GET/HEAD requests continue;
    # form submissions, redirects to other hosts and cross-host resources stop.
    # The invoking World manifest must explicitly permit the hostname.
    class BrowserAgent
      Error = Class.new(StandardError)
      MAX_SESSIONS = 3
      MAX_SESSION_BYTES = 40
      MAX_URL_BYTES = 2_000
      MAX_SCROLL_STEPS = 5
      MAX_SOURCE_BYTES = 24_000
      MAX_TEXT_BYTES = 12_000
      MAX_LINKS = 60
      SENSITIVE_QUERY_KEY = /(?:token|secret|password|passwd|credential|auth|session|otp|one.?time|signature|jwt|api.?key|access.?key|code)/i.freeze

      RESTRICTED = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
        169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
        192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
        203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ].map { |range| IPAddr.new(range) }.freeze

      Session = Struct.new(:browser, :page, :host, :address, :mutex, keyword_init: true)

      SNAPSHOT_JS = <<~'JS'.freeze
        (() => {
          const body = document.body;
          const links = Array.from(document.querySelectorAll("a[href]"))
            .filter(a => a.href && a.innerText.trim())
            .slice(0, 60)
            .map(a => ({ text: a.innerText.trim().slice(0, 160), href: a.href }));
          return {
            url: location.href,
            title: document.title || "",
            ready_state: document.readyState,
            scroll_y: window.scrollY,
            scroll_height: document.documentElement.scrollHeight,
            visible_text: (body ? body.innerText : "").slice(0, 12000),
            source: document.documentElement.outerHTML.slice(0, 24000),
            links
          };
        })()
      JS

      SETTLE_JS = <<~'JS'.freeze
        await new Promise(resolve => {
          let timer;
          const observer = new MutationObserver(() => {
            clearTimeout(timer);
            timer = setTimeout(finish, 350);
          });
          function finish() {
            observer.disconnect();
            resolve(true);
          }
          observer.observe(document.documentElement, {
            childList: true, subtree: true, attributes: true
          });
          timer = setTimeout(finish, 650);
        });
      JS

      def self.available?
        require "ferrum"
        true
      rescue LoadError
        false
      end

      def self.public_ipv4?(value)
        ip = IPAddr.new(value.to_s)
        ip.ipv4? && !RESTRICTED.any? { |range| range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        false
      end

      def initialize(world:)
        @world = world
        @sessions = {}
        @mutex = Mutex.new
      end

      def call(action:, session: "default", url: nil, href: nil, steps: 1)
        key = session_key(session)
        case action.to_s
        when "open" then open(key, url)
        when "inspect" then inspect_page(key)
        when "scroll" then scroll(key, steps)
        when "follow" then follow(key, href)
        when "close" then close(key)
        else
          raise Error, "unknown browser action: #{action}"
        end
      rescue Core::Refusal => e
        { error: "REFUSED by MASTER capability policy: #{e.message}" }
      rescue Error, ArgumentError, URI::InvalidURIError => e
        { error: "Browser could not complete: #{e.message}" }
      rescue StandardError => e
        { error: "Browser failed: #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 180]}" }
      end

      private

      def open(key, raw_url)
        uri = public_uri!(raw_url)
        host = uri.host.downcase
        @world.manifest.check!(:net, host)
        address = resolve_public_ipv4(host)

        raise Error, "session #{key} is already open; close it before opening another page" if lookup(key)
        raise Error, "browser session limit reached (#{MAX_SESSIONS})" if session_count >= MAX_SESSIONS

        require_ferrum!
        browser = Ferrum::Browser.new(
          headless: true,
          timeout: 20,
          process_timeout: 20,
          browser_options: { "host-resolver-rules" => "MAP #{host} #{address}" }
        )
        page = browser.create_page
        secure_page(page, host)
        page.go_to(uri.to_s)
        settle(page)
        state = Session.new(browser:, page:, host:, address:, mutex: Mutex.new)
        register(key, state)
        snapshot(state)
      rescue StandardError
        @mutex.synchronize { @sessions.delete(key) if browser && @sessions[key]&.browser.equal?(browser) }
        browser&.quit
        raise
      end

      def inspect_page(key)
        state = lookup(key) or raise Error, "no browser session: #{key}"
        state.mutex.synchronize { snapshot(state) }
      end

      # Repeated bounded bottom-scrolls trigger lazy content. Each step waits
      # for network idle and DOM mutations; an unchanged page height and text
      # tail is evidence that the feed stopped yielding new material.
      def scroll(key, raw_steps)
        state = lookup(key) or raise Error, "no browser session: #{key}"
        steps = Integer(raw_steps).clamp(1, MAX_SCROLL_STEPS)
        state.mutex.synchronize do
          completed = 0
          reached_end = false
          steps.times do
            before = page_measure(state.page)
            state.page.execute("window.scrollTo(0, document.documentElement.scrollHeight)")
            settle(state.page)
            after = page_measure(state.page)
            completed += 1
            if after == before
              reached_end = true
              break
            end
          end
          result = snapshot(state)
          result[:scroll] = { steps: completed, reached_end: }
          result
        end
      end

      # Follow a literal same-host href by navigation, never by firing
      # arbitrary page handlers that could submit forms or mutate state.
      def follow(key, raw_href)
        state = lookup(key) or raise Error, "no browser session: #{key}"
        raise Error, "href is required" if raw_href.to_s.empty?
        target = URI.join(state.page.url.to_s, raw_href.to_s)
        ensure_bound_host!(state, target)
        @world.manifest.check!(:net, state.host)
        state.mutex.synchronize do
          state.page.go_to(target.to_s)
          settle(state.page)
          snapshot(state)
        end
      end

      def close(key)
        state = @mutex.synchronize { @sessions.delete(key) }
        return { closed: true, session: key } unless state

        state.mutex.synchronize { state.browser.quit }
        { closed: true, session: key }
      end

      def close_all
        states = @mutex.synchronize do
          open = @sessions.values
          @sessions.clear
          open
        end
        states.each do |state|
          state.mutex.synchronize { state.browser.quit }
        rescue StandardError
          nil
        end
        { closed: states.size }
      end

      def secure_page(page, host)
        page.network.intercept
        page.on(:request) do |request|
          begin
            uri = URI(request.url.to_s)
            safe = uri.is_a?(URI::HTTPS) && uri.port == 443 &&
                   uri.host.to_s.downcase == host &&
                   %w[GET HEAD].include?(request.method.to_s.upcase)
            @world.manifest.check!(:net, host) if safe
            safe ? request.continue : request.abort
          rescue StandardError
            request.abort rescue nil
          end
        end
      end

      def settle(page)
        page.network.wait_for_idle(timeout: 8, duration: 0.2, connections: 2)
        page.evaluate(SETTLE_JS, timeout: 2)
      rescue StandardError
        # Long polling and perpetual animation must not hold a turn open.
        # The following snapshot remains an observed, explicitly bounded state.
        nil
      end

      def page_measure(page)
        page.evaluate("({height: document.documentElement.scrollHeight, tail: (document.body ? document.body.innerText : '').slice(-1000)})")
      end

      def snapshot(state)
        data = state.page.evaluate(SNAPSHOT_JS)
        screenshot = state.page.screenshot(encoding: :binary)
        screenshot_path = "log/master/browser-#{state_id(state)}.png"
        @world.write(screenshot_path, screenshot, mode: 0o600)
        data["url"] = redact_url(data["url"])
        data["source"] = data["source"].to_s.byteslice(0, MAX_SOURCE_BYTES).to_s
        data["visible_text"] = data["visible_text"].to_s.byteslice(0, MAX_TEXT_BYTES).to_s
        data["links"] = Array(data["links"]).first(MAX_LINKS).map do |link|
          link.merge("href" => redact_url(link["href"]))
        end
        data["screenshot_file"] = screenshot_path
        data["vision_note"] = "Screenshot saved locally; the current text-only model path has not received image pixels."
        data
      end

      def redact_url(value)
        uri = URI.parse(value.to_s)
        uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s).map do |key, item|
          [key, key.match?(SENSITIVE_QUERY_KEY) ? "[redacted]" : item]
        end) unless uri.query.to_s.empty?
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        "[invalid URL]"
      end

      def public_uri!(raw)
        value = raw.to_s.strip
        raise Error, "url is required" if value.empty?
        raise Error, "url exceeds #{MAX_URL_BYTES} bytes" if value.bytesize > MAX_URL_BYTES

        uri = URI(value)
        unless uri.is_a?(URI::HTTPS) && uri.port == 443 && !uri.host.to_s.empty? && uri.userinfo.nil?
          raise Error, "only public HTTPS URLs without embedded credentials are allowed"
        end
        begin
          IPAddr.new(uri.host)
          raise Error, "IP-literal URLs are not allowed"
        rescue IPAddr::InvalidAddressError
          # Host is a name, not an IP literal.
        end
        uri
      end

      def ensure_bound_host!(state, uri)
        unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.host.to_s.downcase == state.host
          raise Error, "session is bound to #{state.host}; cross-host navigation was refused"
        end
        raise Error, "URL credentials are not allowed" if uri.userinfo
      end

      def resolve_public_ipv4(host)
        addresses = Resolv.getaddresses(host)
        address = addresses.find { |candidate| self.class.public_ipv4?(candidate) }
        raise Error, "no public IPv4 address for #{host}; private, reserved and IPv6-only hosts are refused" unless address

        address
      rescue Resolv::ResolvError => e
        raise Error, "DNS lookup failed for #{host}: #{e.message}"
      end

      def session_key(value)
        key = value.to_s
        raise Error, "invalid session name" unless key.match?(/\A[A-Za-z0-9_-]{1,#{MAX_SESSION_BYTES}}\z/)
        key
      end

      def require_ferrum!
        return if defined?(Ferrum::Browser)
        require "ferrum"
      rescue LoadError
        raise Error, "Ferrum is not installed; install the declared browser dependency before using browser tools"
      end

      def lookup(key) = @mutex.synchronize { @sessions[key] }
      def session_count = @mutex.synchronize { @sessions.size }

      def register(key, state)
        @mutex.synchronize do
          raise Error, "browser session limit reached (#{MAX_SESSIONS})" if @sessions.size >= MAX_SESSIONS
          @sessions[key] = state
        end
      end

      def state_id(state)
        @mutex.synchronize { @sessions.key(state) } || "capture"
      end
    end
  end
end
