# frozen_string_literal: true

require "net/http"
require "socket"
require "uri"
require_relative "utf8"

module CrawlSupport
  module_function

  # One HTTP client for live checks and the optional repository crawler. The
  # Host header distinguishes Brgen's vertical subdomains on a shared loopback
  # port; Accept can narrow a probe to an expected response type.
  def fetch(url, timeout: 15, open_timeout: 8, host: nil, accept: nil)
    uri = URI(url)

    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout:,
                    read_timeout: timeout) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)

      req["Host"] = host if host
      req["Accept"] = accept if accept
      http.request(req)
    end
  end

  # fetch with same-host redirects followed. A first-screen check that stops
  # at a 302 measures a zero-byte body — the auth gate on /profile/new
  # (2026-11-16) failed both landmark needles while the page a visitor actually
  # lands on carries every one of them. The redirect is replayed against the
  # same 127.0.0.1:port with the original options, because the absolute
  # Location names the public host, which this loopback cannot resolve to the
  # app under test. Cross-host redirects are returned unfollowed: that is a
  # routing decision to report, not one to hide.
  def fetch_following(url, limit: 4, **opts)
    origin = URI(url)
    res = fetch(url, **opts)
    hops = 0
    while res.code.to_i.between?(301, 399) && hops < limit &&
          (location = res["location"])
      target = URI(location)
      next res if target.host && target.host != origin.host

      res = fetch(format("%s://%s:%s%s", target.scheme || origin.scheme,
                         origin.host, origin.port, target.request_uri), **opts)
      hops += 1
    end
    res
  end

  def port_open?(host, port, timeout: 0.4, on_error: nil)
    Socket.tcp(host, port, connect_timeout: timeout).close
    true
  rescue StandardError => e
    begin
      on_error&.call(e)
    rescue StandardError
      # Diagnostics must not change the result of a port probe.
    end

    false
  end
end
