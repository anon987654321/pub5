#!/usr/bin/env ruby
# frozen_string_literal: true

# Replays the search flow through the check's own FlowClient — the same
# cookies, CSRF and agent semantics the failing journey uses — and dumps the
# bodies, so the difference between the sim's search and a working curl is
# visible instead of guessed.
ROOT = "/home/z/my-project/pub5/MASTER"
require File.join(ROOT, "checks/support/crawl_support")
require File.join(ROOT, "checks/lib/live/flow_journey")

client = Deploy::FlowJourneyCheck::FlowClient.new(port: 38182, default_host: "brgen.no")

compose = client.get("/posts/new")
puts "compose_form: #{compose.code} (final #{compose.final_path})"
csrf = compose.body[Deploy::FlowJourneyCheck::FlowClient::CSRF_META, 1] ||
       compose.body[Deploy::FlowJourneyCheck::FlowClient::CSRF_FIELD, 1]
puts "csrf: #{csrf ? csrf[0, 12] + "..." : "NONE"}"

unique = "dbg#{Time.now.to_i.to_s(36)}"
publish = client.post("/posts", { post: { title: "Sokeflow #{unique}", content: "finn meg" } })
puts "publish: #{publish.code} (final #{publish.final_path})"
puts "publish body has title: #{publish.body.include?("Sokeflow #{unique}")}"

search = client.get("/search?q=#{unique}")
puts "search: #{search.code} (final #{search.final_path})"
puts "search body has title: #{search.body.include?("Sokeflow #{unique}")}"
File.write("/tmp/sim-search-body.html", search.body)
puts "unique: #{unique}"
