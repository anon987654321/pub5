# frozen_string_literal: true

module Gatekeeper
  # Who wrote a commit, and how far registry/writers.yml trusts them. The
  # Writer: trailer is the only identity: every writer pushes from the same
  # GitHub account and most commit as the operator's name, so the author
  # names nobody. An author listed under inbox_tier_authors (the shared
  # anon987654321 account) is judged at inbox tier whatever its trailer says.
  class Writers
    GATE = "gate"
    UNKNOWN = "unknown"

    def initialize(registry = Core::Registry.load(:writers))
      @writers = registry.fetch("writers")
      @inbox_authors = Array(registry["inbox_tier_authors"])
    end

    def writer(commit)
      return GATE if commit["trailers"].any? { |t| t.match?(/\AGate:\s/i) }

      named = commit["trailers"].filter_map { |t| t[/\AWriter:\s*(\S+)\s*\z/i, 1]&.downcase }.last
      return UNKNOWN unless named

      @writers.key?(named) ? named : "#{UNKNOWN}:#{named}"
    end

    # inbox, main, or nil for the gate itself and an unnamed writer.
    def tier(commit)
      return "inbox" if inbox_author?(commit)

      @writers.dig(writer(commit), "trust")
    end

    def inbox_author?(commit) = @inbox_authors.include?(commit["author"]) || @inbox_authors.any? { |a| commit["email"].to_s.start_with?("#{a}@") }

    # The writer an inbox/<writer>[/<task>] branch belongs to, if writers.yml
    # lists that branch.
    def for_branch(branch)
      name = branch.split("/")[1].to_s
      row = @writers[name]
      row && row.fetch("branches").any? { |b| branch == b || branch.start_with?("#{b}/") } ? name : nil
    end

    def trees(name) = @writers.dig(name, "trees") || []

    def inside?(name, path)
      trees = trees(name)
      trees.include?("all") || trees.include?(path.split("/").first)
    end
  end
end
