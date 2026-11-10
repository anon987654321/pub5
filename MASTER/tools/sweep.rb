# frozen_string_literal: true

# The repo's instruments, run as one pass, reported as a dmesg.
#
# MASTER converges on "no rule fires". That is not the same as "nothing left
# worth doing", and the gap is most of what a refinement pass finds: a rake task
# nothing calls, a backoff that never sleeps, a mailer aimed at a route that does
# not exist, a check asserting on the word "rubocop" rather than on whether it
# ran. No rule in data/laws.yml names any of those, because they are not
# properties of a file — they are properties of a claim and its reader.
#
# What already existed: seven instruments that each answer one such question for
# one population — dup_census, data_reach, reader_singularity, rule_reach,
# namespace_ratchet, design_baseline, cohesion. Each with its own
# invocation, its own ceiling file, and no shared vocabulary. `MASTER/bin/operator measure`
# aggregates the ratchets; nothing aggregates the *questions*.
#
# This does, per tree, in dmesg form, because a sweep that prints a wall of prose
# is a sweep whose middle nobody reads.
#
#   ruby MASTER/tools/sweep.rb MASTER
#   ruby MASTER/tools/sweep.rb --all
#   ruby MASTER/tools/sweep.rb --all --json
#
# It measures and proposes. It does not land: a ratchet can be moved
# mechanically, a regroup cannot, and a tool that edits on its own judgement
# lands changes no person and no WriteGuard has judged. The ledger is what makes the
# loop convergent — see data/proposals.yml.

require "json"
require "yaml"
require_relative "../lib/io/exec"
require_relative "../lib/boot/paths"
require_relative "../lib/trace/dmesg"

module Operator
  module Sweep
    ROOT = File.expand_path("../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    LEDGER = File.join(MASTER, "data", "proposals.yml")

    TREES = MasterPaths::TREES

    # unit name, the tree(s) it speaks for, and how to run it. Each returns
    # [ok, detail] — detail is the dmesg line body, ok is whether the instrument
    # is at or under its recorded low.
    Probe = Struct.new(:unit, :trees, :run, :scoped, keyword_init: true)

    module_function

    def probes
      [
        Probe.new(unit: "spine", trees: %w[MASTER], run: -> { rake("lint:spine") }),
        Probe.new(unit: "cohesion", trees: TREES, scoped: true,
                  run: ->(tree) { tool("cohesion.rb", "--census", "--tree=#{tree}") }),
        Probe.new(unit: "dupcensus", trees: %w[MASTER], run: -> { tool("audit/dup_census.rb") }),
        Probe.new(unit: "datareach", trees: %w[MASTER], run: -> { tool("audit/data_reach.rb") }),
        Probe.new(unit: "readersing", trees: %w[MASTER], run: -> { tool("reader_singularity.rb") }),
        Probe.new(unit: "lawreach", trees: %w[MASTER], run: -> { tool("law_reach.rb") }),
        Probe.new(unit: "namespace", trees: %w[MASTER], run: -> { tool("namespace_ratchet.rb") }),
        Probe.new(unit: "designbase", trees: %w[RAILS], run: -> { tool("audit/design_baseline.rb") }),
# OPENBSD's declarations and their readers live in different files by
# design — crontab names a path, OPERATOR.sh installs it, rc.d holds the
# service, nsd.conf names the zone — and nothing failed when a pair
# stopped agreeing.
Probe.new(unit: "obsdreach", trees: %w[OPENBSD],
          run: -> { sibling("OPENBSD", "bin/reach") }),
# STUDIO's `rake check` parses its Ruby, holds its require boundary and boots
# the guarded entry points; without it STUDIO's heading reports cohesion
# alone. It was `check.rb` until the Rakefile took the work over.
Probe.new(unit: "studiocheck", trees: %w[STUDIO],
          run: -> { sibling_task("STUDIO", "check") }),
# BIZ owns its instrument since the 2026-11-08 one-tree consolidation: the
# bases, the build chain and the published folders share the BIZ tree.
# bp_check re-reads the built HTML and runs the law checks the tree is held
# to; it is the only instrument that speaks for BIZ, and reading its own tree
# is the whole job. It writes to a temp
# directory unless BIZ_OUT_DIR names the tree, which is what makes the check
# read what is committed instead of what was last built.
Probe.new(unit: "bizcheck", trees: %w[BIZ],
          run: -> { biz_check }),
# MASTER/tools's coverage was never thin, only unreported here: check.rb parses
# every first-party file, checks dilla's manifest against the disk, and
# boots the guarded entry points. `rake tools` already runs it; this is
# what makes its result visible in a sweep.
Probe.new(unit: "toolsgate", trees: %w[MASTER],
          run: -> { tool("check.rb") }),
        Probe.new(unit: "instruments", trees: %w[MASTER], run: -> { tool("instruments.rb") }),
        Probe.new(unit: "constcoll", trees: %w[MASTER], run: -> { tool("constant_collisions.rb") }),
        Probe.new(unit: "secsweep", trees: %w[MASTER], run: -> { tool("security_sweep.rb") }),
      ]
    end

    def tool(name, *args)
      capture(RbConfig.ruby, File.join(MASTER, "tools", name), *args)
    end

# Run from the sibling's own directory. MASTER requires nothing from the
# other trees and they resolve their own relative paths; a probe is a
# subprocess for the same reason rake tools check is one.
def sibling(tree, script, *args)
  dir = File.join(ROOT, tree)
  capture(RbConfig.ruby, File.join(dir, script), *args, chdir: dir)
end

# A sibling that is checked by a task rather than a script: STUDIO deleted its
# check.rb when `rake check` took over the work (it loads the tree's
# entrypoints, holds its require boundary and boots the guarded paths). The
# probe follows the tree's own surface instead of naming a file that no
# longer exists.
def sibling_task(tree, task)
  dir = File.join(ROOT, tree)
  capture(RbConfig.ruby, "-S", "rake", task, chdir: dir)
end

# BIZ's instrument is a node script that reads the tree's committed HTML.
def biz_check
  dir = File.join(ROOT, "BIZ")
  capture({ "BIZ_OUT_DIR" => dir }, "node", File.join(ROOT, "BIZ", "tools", "bp_check.mjs"),
          chdir: dir)
end

    def rake(task)
      capture(RbConfig.ruby, "-S", "rake", task, chdir: MASTER)
    end

    def capture(*cmd, chdir: MASTER)
      out, err, status = Master::Io::Exec.capture3(*cmd, chdir:)
      body = "#{out}#{err}".lines.map(&:rstrip).reject(&:empty?)
      [status.success?, body]
    rescue StandardError => e
      [false, ["#{e.class}: #{e.message}"]]
    end

    # One probe result is an execution receipt, not a Law verdict: an instrument
    # may exit successfully while reporting findings above its own recorded low.
    ProbeResult = Struct.new(:tree, :unit, :executed, :process_success, :summary, :evidence,
                             keyword_init: true)

    # The instrument's summary line, not simply the last line printed.
    # design_baseline emits its summary before per-app detail; taking the last
    # line hid a live violation behind the detail row.
    def verdict(body)
      summary = body.reverse.find { |line| line.match?(/\\A[a-z][a-z_]*:\\s/) }
      (summary || body.last).to_s.sub(/\\A\\w+[_a-z]*:\\s*/, "")
    end

    def dmesg(line) = Master::Trace::Dmesg.emit(line.to_s.gsub(/\\s+/, " ").strip, force: true)

    # Detailed mode is consumed by /fix --mode=audit. The default return remains
    # the historic unit/index pairs for the standalone sweep command.
    def sweep(tree, unit_index, detailed: false, stop: nil)
      Master::Trace::Dmesg.attach("#{tree.downcase}0", "sweep0", tree_summary(tree))
      rows = probes.select { |probe| probe.trees.include?(tree) }
      results = []
      rows.each_with_index do |probe, index|
        unit = "#{probe.unit}#{unit_index + index}"
        if stop&.call
          results << ProbeResult.new(tree:, unit:, executed: false, process_success: nil,
                                     summary: "cancelled before probe execution", evidence: [])
          next
        end

        ok, body = begin
          probe.scoped ? probe.run.call(tree) : probe.run.call
        rescue StandardError => error
          [false, ["#{error.class}: #{error.message}"]]
        end
        body = Array(body).map(&:to_s)
        summary = verdict(body)
        evidence = body.reject { |line| line.include?(summary) }.last(4)
        Master::Trace::Dmesg.attach(unit, "#{tree.downcase}0", summary)
        evidence.each { |line| Master::Trace::Dmesg.status(unit, line) } unless ok
        results << ProbeResult.new(tree:, unit:, executed: true, process_success: !!ok,
                                   summary:, evidence:)
      end

      return results if detailed

      rows.map.with_index { |probe, index| [probe.unit, unit_index + index] }
    end

    def tree_summary(tree)
      files = Dir.glob(File.join(ROOT, tree, "**", "*.rb"))
                 .reject { |f| f.match?(%r{/(vendor|node_modules|tmp|\.git|knowledge|output)/}) }
      lines = files.sum { |f| File.foreach(f).count rescue 0 }
      "#{files.size} files, #{lines} lines"
    end

    def ledger
      return { "proposals" => [] } unless File.exist?(LEDGER)

      YAML.safe_load_file(LEDGER) || { "proposals" => [] }
    end

    def ledger_counts
      rows = ledger.fetch("proposals", [])
      rows.group_by { |r| r["state"] }.transform_values(&:size)
    end

    def run(trees, json: false)
      return puts(JSON.pretty_generate(trees: trees.to_h { |t| [t, probes.select { |p| p.trees.include?(t) }.map(&:unit)] })) if json

      Master::Trace::Dmesg.attach("sweep0", "master0", "pub5 root, #{trees.join(", ")}")
      Master::Trace::Dmesg.status("sweep0", "#{Dir.glob(File.join(ROOT, "**", "*.rb")).size} Ruby files, #{probes.size} probes")
      idx = 0
      trees.each { |tree| idx += sweep(tree, idx).size }

      counts = ledger_counts
      Master::Trace::Dmesg.attach("ledger0", "sweep0", "proposals")
      Master::Trace::Dmesg.status("ledger0", "open #{counts["open"].to_i}, landed #{counts["landed"].to_i}, refuted #{counts["refuted"].to_i}")
      Master::Trace::Dmesg.status("sweep0", "root on #{trees.first.downcase}0, swap on ledger0, dump on ledger0")
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  json = ARGV.include?("--json")
  trees = ARGV.include?("--all") ? Operator::Sweep::TREES : ARGV.reject { |a| a.start_with?("--") }
  trees = %w[MASTER] if trees.empty?
  bad = trees - Operator::Sweep::TREES
  unless bad.empty?
    Master::Trace::Dmesg.status("sweep0", "unknown tree(s), #{bad.join(", ")}", io: $stderr)
    exit 64
  end
  exit Operator::Sweep.run(trees, json:)
end
