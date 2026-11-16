#!/usr/bin/env ruby
# frozen_string_literal: true

# Captures amber's root full-page twice — once with Chrome's default fixed
# painting (the artifact), once with pin_fixed (the fix) — as the evidence
# pair for the camera change. Not part of the suite: a one-shot probe.
#
# Usage: ruby scripts/capture_fixed_pair.rb <port> <outdir>
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
require_relative File.join(ROOT, "MASTER/checks/support/cdp_session")

port = ARGV.fetch(0)
outdir = ARGV.fetch(1)

cdp = Deploy::CdpSession.new(host_map: {}).start
begin
  cdp.viewport(390, 844, mobile: true)
  cdp.navigate("http://127.0.0.1:#{port}/", settle: 2.5)
  cdp.evaluate("window.scrollTo(0, document.body.scrollHeight)") # park the scroll the artifact needs
  cdp.evaluate("window.scrollTo(0, 0)")
  sleep 1
  cdp.screenshot(File.join(outdir, "amber_artifact.png"), capture_beyond_viewport: true)
  cdp.screenshot(File.join(outdir, "amber_pinned.png"), capture_beyond_viewport: true, pin_fixed: true)
  puts "captured both"
ensure
  cdp.close
end
