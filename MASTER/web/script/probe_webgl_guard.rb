#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require_relative "../../checks/support/cdp_session"

WEBGL_PAGE = File.join(__dir__, "probe_webgl_guard.html")
TIMEOUT = Integer(ENV.fetch("PROBE_BROWSER_TIMEOUT", "15"))

def report_skip(error)
  puts "probe_webgl_guard: SKIP (#{error.message.lines.first.to_s.strip})"
  puts "set PROBE_REQUIRE_BROWSER=1 to make browser launch failures fatal"
  exit 0
end

def evaluate_probe(cdp, expression)
  cdp.evaluate(expression)
end

html = File.read(WEBGL_PAGE)
url = "data:text/html;base64,#{Base64.strict_encode64(html)}"
browser_started = false

begin
  Deploy::CdpSession.open(timeout: TIMEOUT, webgl: true) do |cdp|
    browser_started = true
    cdp.navigate(url, settle: 0)

    before = evaluate_probe(cdp, <<~JS)
      (() => {
        const canvas = document.getElementById("face");
        return {
          primer: !!document.getElementById("primer"),
          primerFired: !!window._primerFired,
          webgl: !!canvas.getContext("webgl"),
          webgl2: !!canvas.getContext("webgl2")
        };
      })()
    JS

    cdp.evaluate('document.getElementById("primer").click()')

    after = evaluate_probe(cdp, <<~JS)
      (() => {
        const canvas = document.createElement("canvas");
        return {
          primerFired: !!window._primerFired,
          faceSession: document.body.classList.contains("face-session"),
          webgl: !!canvas.getContext("webgl"),
          webgl2: !!canvas.getContext("webgl2")
        };
      })()
    JS

    failures = []
    failures << "primer missing" unless before["primer"]
    failures << "WebGL escaped guard before tap" if before["webgl"] || before["webgl2"]
    failures << "primer did not fire" unless after["primerFired"]
    failures << "face-session missing after tap" unless after["faceSession"]
    failures << "WebGL unavailable after tap" unless after["webgl"] || after["webgl2"]

    puts "probe_webgl_guard: before"
    puts JSON.pretty_generate(before)
    puts "probe_webgl_guard: after"
    puts JSON.pretty_generate(after)

    if failures.empty?
      puts "probe_webgl_guard: PASS"
    else
      puts "probe_webgl_guard: FAIL"
      failures.each { |failure| puts "  - #{failure}" }
      exit_code = 1
    end
  end
  exit(exit_code || 0)
rescue Deploy::CdpSession::Unavailable, Deploy::CdpSession::Timeout, Errno::ENOENT => error
  if browser_started || ENV["PROBE_REQUIRE_BROWSER"] == "1"
    warn "probe_webgl_guard: FAIL (#{error.class}: #{error.message})"
    exit 1
  end

  report_skip(error)
rescue StandardError => error
  warn "probe_webgl_guard: FAIL (#{error.class}: #{error.message})"
  exit 1
end
