#!/usr/bin/env ruby
# frozen_string_literal: true

# Focused verdict on the two live checks the 2026-11-16 journey fixes target.
# The full runner wedged mid-run (see TODO), so the arbiter for the fixes is
# the checks themselves, standalone, with the fleet up on its triangle ports.
ROOT = "/home/z/my-project/pub5/MASTER"
$LOAD_PATH.unshift(File.join(ROOT, "checks"))
Dir.chdir(ROOT)

require File.join(ROOT, "checks/support/crawl_support")
require File.join(ROOT, "checks/lib/live/flow_journey")
require File.join(ROOT, "checks/lib/live/page_simulation")

which = ARGV.fetch(0, "both")
if %w[both flow].include?(which)
  result = Deploy::FlowJourneyCheck.new.run
  puts "FLOW_JOURNEY: #{result.summary rescue result.inspect[0, 200]}"
end
if %w[both sim].include?(which)
  result = Deploy::PageSimulationCheck.new.run
  puts "PAGE_SIMULATION: #{result.summary rescue result.inspect[0, 200]}"
end
