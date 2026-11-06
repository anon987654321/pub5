# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/universal.rb:301 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 7ad97b152dac0b7d
require_relative "master/law/universal"

Law.define(:UNBOUNDED_RETRY) do
  source "Release It! - retry budgets / bounded retries (Nygard)"
  # Every finding this produced was a false positive, all five of them. Three
  # narrowings, each against one of those shapes:
  #
  # A retry whose modifier bounds it IS the fix — `retry if attempts < RETRIES`
  # is what "add a max_attempts cap" looks like once someone has added it, and
  # flagging it asks for the change that is already there.
  #
  # `while true` left the rule. A supervisor loop that sleeps is not a retry: it
  # is how every watcher in this tree is written, the bad fixture below is a
  # bare `retry` rather than a loop, and the one hit was OPENBSD's file watcher
  # doing its job. A rule about busy loops needs to see the body for a sleep,
  # which is file scope and a different rule.
  #
  # The keyword has to be a statement. String blanking cannot survive a nested
  # interpolation — `"CSS#{a ? " (retry)" : ""}"` left the word bare — and a
  # `retry` that is not at the head of a statement is prose in every case.
  #
  # One line on purpose: Law.conduct neutralizes `detect` lines when a law
  # judges law/, and it reads lines, not blocks.
  detect { |line| (s = line.strip) && !s.start_with?("#") && !s.match?(/retry\\/) && !s.match?(/\bretry\s+(?:if|unless)\b[^\n]*[<>]/) && (b = s.gsub(/"(?:\\.|[^"\\])*"/, '""').gsub(/'[^']*'/, "''")) && b.match?(/\A(?:.*(?:;|\bthen\b|\bdo\b)\s*)?retry(?![?:\w|])/) || false }
  fix "Add max_attempts cap and exponential backoff."
  bad "retry"
  good <<~'X'
    next if action == :retry
    def retry?(error, attempt:)
    @bus&.publish("llm:failover_backoff", retry: retry_index + 1)
    [+0.18, :name, /retry|loop|escalat/],
    # a retry then spawned a duplicate on the same output file
    attempts += 1 and redo if attempts < 3
    message: "retry with no visible attempt counter",
    lines << "refresh %s retry" % policy.dig("soa", "retry")
  X
end
