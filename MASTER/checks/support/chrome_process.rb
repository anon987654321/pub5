# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Deploy
  # The browser as a process: where Chrome is, how it is launched, how its
  # debugging port is discovered, and how it is reaped.
  #
  # Split out when cdp_session.rb passed its file-length ceiling a second time.
  # The first split took the RFC 6455 half into cdp_framing.rb; this is the
  # other seam in the same file — everything left in CdpSession speaks the
  # DevTools Protocol to a browser that is already running, and nothing here
  # knows what CDP is.
  #
  # Timeout is spelled CdpSession::Timeout throughout. Bare `Timeout` resolves
  # to the stdlib module, and it resolves at the moment the deadline is hit —
  # a NameError instead of the error the caller rescues. That is the failure
  # cdp_framing.rb's own comment records from the first split.
  module ChromeProcess
    CHROME_PATHS = [
      ENV["CHROME_PATH"],
      "/usr/local/bin/chromium",
      "/usr/local/bin/chrome",
      "/usr/local/chrome/chrome",
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/usr/bin/chromium",
      "/usr/bin/google-chrome",
    ].compact.freeze

    # Asked of the class, because every rendered suite checks on
    # CdpSession.available? before it considers spawning anything.
    module Discovery
      def chrome_path
        candidates = [ENV["CHROME_PATH"], *CHROME_PATHS].compact.uniq
        candidates.find { |path| File.executable?(path) }
      end

      def available?
        !chrome_path.nil?
      end
    end

    TERM_GRACE_S = 5.0
    KILL_GRACE_S = 2.0
    STOP_POLL_S = 0.05

    # Chrome owns a process group created specifically for this session. Its
    # renderer/GPU/network children must not outlive the browser leader and keep
    # writing into the profile while teardown removes it.
    #
    # Do not forget the PID or remove the profile unless both facts are proved:
    # the direct child has been reaped, and its process group no longer exists.
    # If a signal is refused or a child remains, retain the PGID for a later
    # cleanup attempt and leave the profile as evidence.
    def reap_chrome
      pid = @pid
      return true unless pid

      signal_chrome_group("TERM", pid)
      deadline = monotonic + TERM_GRACE_S
      leader_reaped = false

      loop do
        leader_reaped ||= reap_chrome_leader(pid)
        break if leader_reaped && !chrome_group_alive?(pid)
        break if monotonic >= deadline

        sleep STOP_POLL_S
      end

      signal_chrome_group("KILL", pid) unless leader_reaped && !chrome_group_alive?(pid)
      deadline = monotonic + KILL_GRACE_S

      loop do
        leader_reaped ||= reap_chrome_leader(pid)
        break if leader_reaped && !chrome_group_alive?(pid)
        break if monotonic >= deadline

        sleep STOP_POLL_S
      end

      stopped = leader_reaped && !chrome_group_alive?(pid)
      @pid = nil if stopped
      stopped
    rescue StandardError => e
      warn "CDP Chrome cleanup inconclusive for PID #{pid}: #{e.class}: #{e.message}"
      false
    end

    def reap_chrome_leader(pid)
      Process.waitpid(pid, Process::WNOHANG)
      true
    rescue Errno::ECHILD
      true
    rescue Errno::EINTR
      retry
    end

    def chrome_group_alive?(pid)
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def signal_chrome_group(signal, pid)
      Process.kill(signal, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      false
    end

    def spawn_chrome(chrome)
      args = [
        chrome,
        "--headless=new",
        "--remote-debugging-port=0",
        "--user-data-dir=#{@profile}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--disable-background-networking",
        "--disable-sync",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--force-color-profile=srgb",
        "--font-render-hinting=none",
        "--disable-lcd-text",
        "--disable-features=NetworkService,TranslateUI,BackForwardCache",
        "--mute-audio",
        # --disable-gpu turns WebGL off entirely, which is right for the layout
        # and CSS checks this session was written for — software GL is slow and
        # rasterises text differently. It is wrong for a surface made of WebGL:
        # MapLibre and the MASTER face both measured as an empty canvas, so a
        # check asserting "the map draws" would have passed or failed for reasons
        # that had nothing to do with the map. SwiftShader is the opt-in.
        *(@webgl ? [ "--use-angle=swiftshader", "--enable-unsafe-swiftshader" ] : [ "--disable-gpu" ]),
        "about:blank",
      ]

      unless @host_map.empty?
        rules = @host_map.map { |host, target| "MAP #{host} #{target}" }.join(", ")
        args.insert(-2, "--host-resolver-rules=#{rules}")
      end
      # Keep every browser helper in a process group owned by this CDP session.
      spawn(*args, out: File::NULL, err: File::NULL, pgroup: true)
    end

    def devtools_port
      port_file = File.join(@profile, "DevToolsActivePort")
      deadline = monotonic + @timeout
      loop do
        if File.file?(port_file)
          line = File.read(port_file).lines.first.to_s.strip
          return line.to_i if line.to_i.positive?
        end
        raise CdpSession::Timeout, "Chrome never wrote DevToolsActivePort" if monotonic > deadline

        sleep 0.05
      end
    end

    def discover_page_target
      port = devtools_port
      deadline = monotonic + @timeout
      loop do
        body = begin
          Net::HTTP.get(URI("http://127.0.0.1:#{port}/json/list"))
        rescue StandardError # scan: intentional — one poll in the discovery loop; nil retries
          nil
        end

        if body
          targets = JSON.parse(body) rescue []
          page = targets.find { |t| t["type"] == "page" && t["webSocketDebuggerUrl"] }
          return page["webSocketDebuggerUrl"] if page
        end
        raise CdpSession::Timeout, "no CDP page target on port #{port}" if monotonic > deadline

        sleep 0.05
      end
    end
  end
end
