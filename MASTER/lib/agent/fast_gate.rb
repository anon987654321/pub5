# frozen_string_literal: true

# bin/master selfcheck --fast - the seconds-scale self-consistency gate.
#
# The constitution broke its own rules between full audits: a body budget
# overrun of 958 lines, a bin door past its ceiling, a RUNBOOK cron table
# that drifted from fourteen jobs to eleven. None of that needs 48 minutes;
# all of it is mechanical. This gate reads the same declared numbers the
# full ratchets read (spine.yml's ceilings, the RUNBOOK's own table, the
# mirror crontab) and answers in seconds. A green always carries the
# revision it measured; a gate that could not run a check marks it NOT_RUN,
# never PASS.

require "yaml"
require "open3"

module Master
  module Agent
    module FastGate
      extend Base

      class << self
        include Base

        def run(argv)
          fast = !argv.include?("--slow")
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          checks = []
          checks << yaml_health
          checks << catalogue_health
          checks << body_budget
          checks << bin_doors
          checks << cron_table
          checks << hooks_wired
          checks << changed_sources_parse if fast == false || changed_files.any?
          checks << index_freshness
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)

          failed = checks.count { |c| c[:status] == "FAIL" }
          not_run = checks.count { |c| c[:status] == "NOT_RUN" }
          emit(
            command: "selfcheck --fast",
            verdict: failed.zero? ? "PASS" : "FAIL",
            revision: head_revision,
            elapsed_s: elapsed,
            summary: { checks: checks.size, failed:, not_run: },
            checks:,
            note: "a green carries this revision; between full audits this gate is the thing that notices drift",
          )
          failed.zero? ? 0 : 1
        end

        def head_revision
          out, = Open3.capture2("git", "-C", repo_root, "rev-parse", "--short", "HEAD")
          out.strip
        rescue StandardError
          "unknown"
        end

        def check(name, status, detail)
          { name:, status:, detail: }
        end

        def yaml_health
          files = %w[laws.yml gaps.yml proposals.yml operator_seams.yml budgets.yml].map { |f| data_path(f) }
          files.each do |file|
            load_yaml(file)
          rescue SystemExit, StandardError => e
            return check("yaml_health", "FAIL", "#{File.basename(file)} does not parse: #{e.message}")
          end
          check("yaml_health", "PASS", "#{files.size} ledgers parse")
        end

        def catalogue_health
          bad = catalogue_entries.reject { |_id, row| row.is_a?(Hash) && !row["severity"].to_s.empty? }
          return check("catalogue_severity", "FAIL", "entries without severity: #{bad.keys.first(5)}") unless bad.empty?

          non_array = catalogue_entries.select do |_id, row|
            row.is_a?(Hash) && %w[languages surfaces definition_sources].any? do |f|
              row.key?(f) && !row[f].is_a?(Array)
            end
          end
          return check("catalogue_list_fields", "FAIL", "list-typed fields hold scalars: #{non_array.keys.first(5)}") unless non_array.empty?

          check("catalogue_severity", "PASS", "#{catalogue_entries.size} entries all carry severity and list-typed fields")
        end

        # The spine ratchet's own number, counted the way CodeMetrics counts
        # it: non-blank non-comment lines minus Zeitwerk ceremony (a module
        # whose body is exactly one module or class). Ported shape, same rule.
        def body_budget
          ceiling = load_yaml(data_path("spine.yml")).fetch("spine").fetch("lib_body_ceiling")
          require "prism"
          lines = 0
          Dir.glob(File.join(master_root, "lib", "**", "*.rb")).each do |file|
            src = File.read(file)
            result = Prism.parse(src)
            ceremony = result.success? ? count_namespaces(result.value) : 0
            lines += body_lines(src) - ceremony
          end
          over = lines - ceiling
          if over.positive?
            check("lib_body_ceiling", "FAIL", "#{lines} body lines against a ceiling of #{ceiling} (#{over} over; raise it with a sponsor, do not pad)")
          else
            check("lib_body_ceiling", "PASS", "#{lines} body lines against a ceiling of #{ceiling}")
          end
        end

        def body_lines(src)
          src.each_line.count do |line|
            stripped = line.strip
            next false if stripped.empty? || stripped.start_with?("#")

            true
          end
        end

        def count_namespaces(node)
          return 0 unless node.respond_to?(:child_nodes)

          own = pure_namespace?(node) ? 2 : 0
          node.child_nodes.compact.sum(own) { |child| count_namespaces(child) }
        end

        # Two lines: the `module` and its `end`.
        def pure_namespace?(node)
          return false unless node.is_a?(Prism::ModuleNode) || node.is_a?(Prism::ClassNode)

          statements = node.body || node
          return false unless statements.is_a?(Prism::StatementsNode)
          return false unless statements.body.size == 1

          statements.body.first.is_a?(Prism::ModuleNode) || statements.body.first.is_a?(Prism::ClassNode)
        end

        def bin_doors
          bins = Dir.children(File.join(master_root, "bin")).count
          # The ceiling the tree declared: read from the same place rake reads
          # it when it exists; otherwise this check says what it is measuring.
          declared = load_yaml(data_path("spine.yml")).fetch("spine").fetch("bin_entries_ceiling", nil)
          return check("bin_doors", "NOT_RUN", "no bin_entries_ceiling declared in spine.yml; #{bins} bin entries measured, unjudged") unless declared

          bins > declared ? check("bin_doors", "FAIL", "#{bins} bin doors against a ceiling of #{declared}") :
                            check("bin_doors", "PASS", "#{bins} bin doors against a ceiling of #{declared}")
        end

        # The RUNBOOK's own cron table against the tracked mirror crontab.
        # This exact table drifted from fourteen rows to eleven once.
        def cron_table
          runbook = File.join(repo_root, "OPENBSD", "RUNBOOK.md")
          crontab = File.join(repo_root, "OPENBSD", "mirror", "etc", "crontab.vm23")
          return check("cron_table", "NOT_RUN", "RUNBOOK.md or mirror crontab absent") unless File.file?(runbook) && File.file?(crontab)

          body = File.read(runbook)
          section = body[/## Self-healing cron.*?(?=\n## )/m]
          return check("cron_table", "NOT_RUN", "no 'Self-healing cron' section in RUNBOOK.md") unless section

          # A table row that declares itself tracked-and-never-installed is not
          # drift: the table is the register of that fact. Only rows that claim
          # to run are compared against the mirror crontab.
          claimed = []
          all_scripts = []
          section.scan(/^\|\s*`([^`]+)`\s*\|\s*([^|]+)\|([^|]*)\|/).each do |script, _schedule, note|
            name = script.split(/\s+/).first
            next if name.nil?

            all_scripts << name
            claimed << name if note.to_s !~ /never installed|not in root|not in the|daily\.local/i
          end

          live = File.readlines(crontab).grep(/^\S/).reject { |l| l.start_with?("#") }
          live_scripts = live.filter_map do |line|
            fields = line.split(/\s+/)
            command = fields.drop(5).drop_while { |tok| tok.match?(/\A[A-Z_]+=/) }.first
            command ? File.basename(command) : nil
          end
          missing = claimed - live_scripts
          unknown = live_scripts - all_scripts.uniq
          if missing.empty? && unknown.empty?
            tracked = all_scripts.size - claimed.size
            check("cron_table", "PASS",
                  "mirror crontab matches the RUNBOOK table: #{claimed.size} installed + #{tracked} tracked-not-installed = #{all_scripts.size} jobs")
          else
            check("cron_table", "FAIL",
                  "mirror crontab and RUNBOOK table disagree; missing from crontab: #{missing.first(3)}, " \
                  "unknown to the table: #{unknown.first(3)}")
          end
        end

        def hooks_wired
          out, = Open3.capture2("git", "-C", repo_root, "config", "--get", "core.hooksPath")
          path = out.strip
          path.empty? ? check("hooks_wired", "FAIL", "core.hooksPath unset: the landing gate never fires; run bin/master hooks install") :
                        check("hooks_wired", "PASS", "core.hooksPath = #{path}")
        end

        def changed_files
          @changed_files ||= begin
            out, = Open3.capture2("git", "-C", repo_root, "diff", "--name-only", "HEAD")
            out.split("\n").map(&:strip).reject(&:empty?)
          rescue StandardError
            []
          end
        end

        def changed_sources_parse
          rubies = changed_files.select { |f| f.end_with?(".rb") && f.start_with?("MASTER/") }
          shells = changed_files.select { |f| f.match?(/\.(sh|ksh|zsh)\z/) }
          return check("changed_sources_parse", "PASS", "no changed sources") if rubies.empty? && shells.empty?

          require "prism"
          bad = rubies.reject do |f|
            full = File.join(repo_root, f)
            !File.file?(full) || Prism.parse(File.read(full)).success?
          end
          return check("changed_sources_parse", "FAIL", "Ruby does not parse: #{bad.join(', ')}") unless bad.empty?

          shell_bad = shells.reject do |f|
            _out, status = Open3.capture2("sh", "-n", File.join(repo_root, f))
            status.success?
          end
          return check("changed_sources_parse", "FAIL", "shell syntax: #{shell_bad.join(', ')}") unless shell_bad.empty?

          check("changed_sources_parse", "PASS", "#{rubies.size} ruby and #{shells.size} shell changed files parse")
        end

        def index_freshness
          index_file = data_path("laws_index.json")
          unless File.file?(index_file)
            require_relative "law_index"
            LawIndex.write_index!
            return check("laws_index", "PASS", "index generated fresh at #{head_revision}")
          end

          idx = JSON.parse(File.read(index_file))
          return check("laws_index", "PASS", "index is current at #{idx['revision']}") if idx["revision"] == head_revision

          # The index can never be fresh at the commit that carries it, so the
          # gate regenerates it here instead of teaching every landing to run
          # laws --reindex by hand. Self-healing, cheap, and the artifact an
          # outside agent fetches is never older than the tree it describes.
          require_relative "law_index"
          LawIndex.write_index!
          check("laws_index", "PASS", "index regenerated from #{idx['revision']} to #{head_revision}")
        end
      end
    end
  end
end
