# frozen_string_literal: true

# bin/master predict PATH - the gate's opinion before the gate.
#
# The selfcheck catches a breach at landing; prediction names it before.
# Files that churn together arm together: a commit touching one member of a
# co-change cluster is likely to surface the cluster's dormant findings in
# its neighbours. This command mines the co-change clusters from git's own
# history, runs the bare scanner over the neighbours now, and answers with
# the warning and the cheapest preventive proof - a seconds-scale scan, not
# a rendered audit. Where the receipt ledger has accumulated outcomes, the
# per-law pass rate is carried along; where it has not, that is said.

require "json"
require_relative "fast_gate"
require "open3"
require "tmpdir"
require "fileutils"

module Master
  module Agent
    module Predict
      extend Base

      class << self
        include Base

        def run(argv)
          path = argv.first
          refuse("predict", "no PATH given", "a path you are about to commit, e.g. MASTER/lib/cli") if path.nil?

          target = normalize(path)
          refuse("predict", "#{path} is not in the working tree", "a path inside the checkout") unless File.exist?(File.join(repo_root, target))

          clusters = co_change_clusters
          cluster_mates = clusters[target] || []
          predictions = cluster_mates.first(8).filter_map do |mate|
            findings = scan_relative(mate)
            next nil if findings.empty?

            { file: mate, would_show_findings: findings.size,
              laws: findings.map { |f| f[:law] }.uniq.first(5),
              cheapest_preventive_proof: "bin/master scan --bare #{mate} - seconds, no bundle; " \
                                         "fix what it shows now and the cluster's next landing is quiet" }
          end

          outcomes = receipt_outcomes
          emit(
            command: "predict",
            path: target,
            cluster_size: cluster_mates.size,
            commits_sampled: SAMPLE_COMMITS,
            predictions:,
            receipt_outcomes: outcomes,
            note: if predictions.empty?
                   "no dormant findings in the co-change cluster; the gate's later opinion is unlikely to surprise"
                 else
                   "these neighbours churn with #{target}; fixing their findings now is cheaper than re-arming at landing"
                 end,
          )
          predictions.empty? ? 0 : 1
        end

        SAMPLE_COMMITS = 400

        private

        def normalize(path)
          path.delete_prefix("/").sub(/\AMASTER\//, "MASTER/").sub(%r{\A(?!MASTER/|RAILS/|OPENBSD/|STUDIO/|BIZ/)}, "MASTER/")
        end

        # Files that land in commits together, from git's own record. A file
        # pair appearing together twice or more is a cluster edge.
        def co_change_clusters
          out, = Open3.capture2("git", "-C", repo_root, "log", "--name-only", "--pretty=format:",
                                "-n", SAMPLE_COMMITS.to_s)
          commits = out.split(/\n{2,}/).map { |block| block.split("\n").map(&:strip).reject(&:empty?) }
          counts = Hash.new { |h, k| h[k] = Hash.new(0) }
          commits.each do |files|
            files.sort.combination(2).each { |a, b| counts[a][b] += 1 }
          end
          clusters = Hash.new { |h, k| h[k] = [] }
          counts.each do |file, mates|
            mates.each do |mate, n|
              next unless n >= 2

              clusters[file] << mate
              clusters[mate] << file
            end
          end
          clusters.transform_values { |mates| mates.uniq.sort }
        end

        def scan_relative(relative)
          require_relative "bare_scan"
          corpus = BareScan.load_corpus("lexical")
          corpus.scan_file(File.join(repo_root, relative))
        rescue StandardError
          []
        end

        def receipt_outcomes
          ledger = File.join(master_root, "data", "receipts", "ledger.jsonl")
          return "no receipts recorded yet" unless File.file?(ledger)

          rows = File.readlines(ledger).filter_map { |l| JSON.parse(l) rescue nil }
          return "no receipts recorded yet" if rows.empty?

          by_law = rows.group_by { |r| r["law"] }
          by_law.to_h { |law, rs| [law, { total: rs.size, pass: rs.count { |r| r["claim"] == "PASS" } }] }
        end
      end
    end
  end
end
