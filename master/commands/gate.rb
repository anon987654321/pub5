# frozen_string_literal: true

require "json"
require "time"
require_relative "../gate/keeper"

module Commands
  # `bin/master gate`: pub5's gatekeeper, run from cron on the box (install
  # kit: openbsd/gatekeeper/README.md). There are no GitHub Actions and no
  # branch protection, so this is the only enforcement: it judges main after
  # the fact and merges inbox branches before. `--status` prints the last
  # results from the ledger and judges nothing.
  #
  # One run at a time: the lock is refs/gate/lock, created with git's
  # compare-and-swap (`update-ref <ref> <new> ""` fails if the ref exists),
  # so two overlapping runs cannot both take it. A run killed by SIGKILL
  # leaves it behind; after STALE_AFTER seconds the next run breaks it.
  class Gate
    LOCK_REF = "refs/gate/lock"
    LOCK_NOTE = "log/gate/lock.json"
    STALE_AFTER = 4 * 3600

    def initialize(world:, context:, out: $stdout, knobs: Core::Knobs.default, writers: nil)
      @world = world
      @out = out
      @knobs = knobs
      @writers = writers
      @repo = ::Gatekeeper::Repo.new(world)
    end

    def call(argv)
      return status if argv.include?("--status")

      locked { ::Gatekeeper::Keeper.new(world: @world, out: @out, knobs: @knobs, **({ writers: @writers }.compact)).call }
    rescue ::Gatekeeper::Failure => e
      @out.puts "gate: FAILED #{e.message}"
      1
    end

    private

    def locked
      head = @repo.out!("rev-parse", "HEAD")
      unless take(head)
        @out.puts "gate: skipped, locked (#{holder || 'holder unknown'}); a stale lock clears after #{STALE_AFTER}s"
        return 0
      end

      begin
        @world.write(LOCK_NOTE, JSON.generate("at" => Time.now.utc.iso8601, "pid" => Process.pid))
        yield
      ensure
        @repo.run("update-ref", "-d", LOCK_REF)
      end
    end

    def take(head)
      return true if @repo.ok?("update-ref", LOCK_REF, head, "")
      return false unless stale?

      @out.puts "gate: breaking a stale lock (#{holder})"
      @repo.run("update-ref", "-d", LOCK_REF)
      @repo.ok?("update-ref", LOCK_REF, head, "")
    end

    def note
      JSON.parse(@world.read(LOCK_NOTE))
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end

    def holder = note && "pid #{note['pid']} since #{note['at']}"

    # A note older than the ref means the note is a previous run's; only a
    # note at least STALE_AFTER old is trusted to mean the holder died.
    def stale?
      at = note && Time.iso8601(note["at"])
      at ? Time.now.utc - at > STALE_AFTER : false
    rescue ArgumentError
      false
    end

    def status
      gate = @world.ledger.entries.select { |e| e["kind"] == "gate" }
      verdicts = gate.select { |e| e["event"] == "verdict" && e["ref"] == ::Gatekeeper::Keeper::BRANCH }
      if verdicts.empty?
        @out.puts "gate: no verdicts yet"
        return 0
      end

      verdicts.last(5).each do |v|
        @out.puts "gate: #{v['sha'][0, 10]} #{v['result']} #{v['writer']} #{v['author']} " \
                  "#{"#{v['step']} " if v['step']}#{v['seconds']}s #{v['at']}"
      end
      marker = File.join(@world.manifest.root, ::Gatekeeper::Keeper::MARKER)
      @out.puts(File.exist?(marker) ? "gate: main red: #{@world.read(::Gatekeeper::Keeper::MARKER).lines.first.strip}" : "gate: main green")
      gate.select { |e| e["event"] == "inbox" }.group_by { |e| e["branch"] }.each_value do |rows|
        r = rows.last
        @out.puts "gate: #{r['branch']} #{r['tip'][0, 10]} #{r['decision']}#{": #{r['reason']}" if r['reason']}"
      end
      violations = gate.select { |e| e["event"] == "violation" }
      violations.last(3).each do |v|
        @out.puts "gate: violation #{(v['sha'] || '')[0, 10]} #{v['writer'] || '-'} #{v['reason']}#{" (#{v['old'][0, 10]} -> #{v['new'][0, 10]})" if v['old']}"
      end
      @out.puts "gate: #{violations.size} violations in all" if violations.size > 3
      0
    end
  end
end
