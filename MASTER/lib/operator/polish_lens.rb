# frozen_string_literal: true

require "json"
require "set"

module Operator
  # PolishLens identifies mechanical, single-owner polishing opportunities and
  # emits them as /fix-compatible candidates. It is the discovery half of polish
  # in /fix: read-only, deterministic, grounded in the existing Laws. It invents
  # no new requirement and no new backlog; implementation stays with the existing
  # /fix pipeline, its budgets, veto and Council. Rendered values, taste and
  # listening decisions are never auto-applied; they remain operator-owned.
  #
  # A check that flags most of what it reads describes the codebase instead of
  # enforcing a rule (see Operator::LawAudit#saturation). Each check therefore
  # respects context: the tree is legitimately polyglot, OPENBSD/mirror files
  # carry intentional target-host paths, and CLAUDE.md is the hand-written
  # bootstrap, not a generated peer.
  #
  #   ruby MASTER/tools/polish_lens.rb               # human table
  #   ruby MASTER/tools/polish_lens.rb --json        # findings
  #   ruby MASTER/tools/polish_lens.rb --candidates  # /fix candidate intake
  module PolishLens
    MASTER = File.expand_path("../..", __dir__)
    ROOT = File.expand_path("..", MASTER)

    Finding = Struct.new(:id, :path, :line, :law, :kind, :detail, :edit, :proof, :cost, :reversibility, keyword_init: true)

    CHECKS = %w[
      keep_hygiene empty_dirs shebang_portability exec_bit fixture_extension
      fixture_mirror generated_banner pointer_symmetry doc_links
    ].freeze

    module_function

    # Pure, deterministic discovery. The CLI and /fix consume the same
    # findings; discovery itself never writes files, creates missions or emits
    # a second backlog.
    def findings(root: ROOT)
      CHECKS.flat_map { |check| send(check, root) }
        .sort_by { |finding| [finding.path, finding.line.to_i, finding.id] }
    end

    # /fix may only act on findings whose exact file is already inside its
    # transaction scope. Directory-only findings remain available to the
    # read-only report but cannot expand a repair pass's ownership boundary.
    def findings_for_paths(root: ROOT, paths:)
      root_real = File.realpath(root)
      owned = Array(paths).filter_map do |path|
        absolute = File.expand_path(path.to_s, root_real)
        next unless absolute.start_with?(root_real + File::SEPARATOR)
        next if File.symlink?(absolute)
        next unless File.file?(absolute)

        real = File.realpath(absolute)
        real if real.start_with?(root_real + File::SEPARATOR)
      rescue SystemCallError
        nil
      end.to_set

      scoped = owned.to_a
      [
        *keep_hygiene(root_real, paths: scoped),
        *shebang_portability(root_real, paths: scoped),
        *exec_bit(root_real, paths: scoped),
        *fixture_extension(root_real, paths: scoped),
        *generated_banner(root_real, paths: scoped),
        *pointer_symmetry(root_real, paths: scoped),
        *doc_links(root_real, paths: scoped),
      ].sort_by { |finding| [finding.path, finding.line.to_i, finding.id] }
    end

    def run(root: ROOT, json: false, candidates: false)
      findings = findings(root:)
      if candidates
        puts JSON.pretty_generate(to_candidates(findings))
      elsif json
        puts JSON.pretty_generate(findings.map(&:to_h))
      else
        report(findings)
      end
      findings
    end

    def to_candidates(findings)
      {
        "schema" => 1,
        "source" => "Operator::PolishLens",
        "note" => "Mechanical polish candidates for the existing /fix intake; " \
                  "rendered/taste items are excluded and remain operator-owned.",
        "candidates" => findings.map do |f|
          {
            "id" => "polish_#{f.id}", "tree" => f.path.split("/").first,
            "law" => f.law, "kind" => f.kind, "path" => f.path, "line" => f.line,
            "spec" => f.detail, "proposed_edit" => f.edit, "proof" => f.proof,
            "cost" => f.cost, "reversibility" => f.reversibility, "status" => "candidate"
          }
        end
      }
    end

    def report(findings)
      if findings.empty?
        puts "polish: no mechanical opportunities found"
        return
      end
      puts "polish: #{findings.size} mechanical opportunities (rendered/taste excluded)"
      findings.each { |f| puts format("%-22s %-50s %s", f.id, "#{f.path}:#{f.line}", f.detail) }
    end

    def rel(root, path) = path.sub("#{root}/", "")

    def files(root)
      Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).reject { |p| p =~ %r{/\.git/} || File.directory?(p) }
    end

    def keep_hygiene(root, paths: nil)
      keepers = paths ? paths.select { |path| File.basename(path) == ".keep" } : Dir.glob("#{root}/**/.keep")
      keepers.filter_map do |k|
        dir = File.dirname(k)
        real = Dir.children(dir).reject { |c| c == ".keep" }
        next if real.empty?
        Finding.new(id: "keep_hygiene", path: rel(root, k), line: 1, law: "DENSITY",
                    kind: "remove", detail: ".keep in a directory that now holds #{real.size} real entries",
                    edit: "delete #{rel(root, k)}", proof: "ruby MASTER/tools/polish_lens.rb --json",
                    cost: "trivial", reversibility: "git revert")
      end
    end

    def empty_dirs(root)
      Dir.glob("#{root}/**/").filter_map do |d|
        next if d =~ %r{/\.git/}
        next unless Dir.children(d).empty?
        Finding.new(id: "empty_dir", path: rel(root, d.chomp("/")), line: 0, law: "DENSITY",
                    kind: "remove", detail: "empty directory no contract names",
                    edit: "remove #{rel(root, d.chomp("/"))} or add a .keep with a purpose comment",
                    proof: "ruby MASTER/tools/polish_lens.rb --json", cost: "trivial", reversibility: "git revert")
      end
    end

    # The tree is legitimately polyglot (ruby, zsh, ksh, sh). Only an absolute
    # interpreter path that `env` would resolve portably is a defect, and never
    # in OPENBSD/mirror, where the target host's absolute paths are intentional.
    def shebang_portability(root, paths: nil)
      (paths || files(root)).filter_map do |f|
        next unless (File.binread(f, 2) == "#!" rescue false)
        next if rel(root, f).start_with?("OPENBSD/mirror/")
        line = File.open(f, &:readline).strip
        next unless line =~ %r{^#!/usr/(local/)?bin/ruby\b}
        Finding.new(id: "shebang_portability", path: rel(root, f), line: 1, law: "POLA",
                    kind: "align", detail: "absolute ruby shebang #{line.inspect} breaks when the interpreter moves",
                    edit: "use #!/usr/bin/env ruby", proof: "ruby -c #{rel(root, f)}",
                    cost: "trivial", reversibility: "git revert")
      end
    end

    def exec_bit(root, paths: nil)
      candidates = paths ? paths.select { |path| rel(root, path).match?(%r{\\AMASTER/bin/[^/]+\\z}) } : Dir.glob("#{root}/MASTER/bin/*")
      candidates.filter_map do |f|
        next if File.directory?(f)
        next if File.executable?(f)
        Finding.new(id: "exec_bit", path: rel(root, f), line: 0, law: "POLA",
                    kind: "chmod", detail: "bin/ entry is not executable",
                    edit: "chmod +x #{rel(root, f)}", proof: "test -x #{rel(root, f)}",
                    cost: "trivial", reversibility: "chmod -x")
      end
    end

    def fixture_extension(root, paths: nil)
      candidates = paths ? paths.select { |path| rel(root, path).start_with?("MASTER/test/fixtures/") } : Dir.glob("#{root}/MASTER/test/fixtures/**/*")
      candidates.filter_map do |f|
        next if File.directory?(f)
        base = File.basename(f)
        next unless base == "-" || File.extname(base).empty?
        Finding.new(id: "fixture_extension", path: rel(root, f), line: 1, law: "TRUTHFUL_STATUS",
                    kind: "rename", detail: "fixture lacks a real extension; proof may differ from production",
                    edit: "give the fixture the extension its language uses", proof: "ruby MASTER/tools/law_fixtures.rb",
                    cost: "small", reversibility: "git revert")
      end
    end

    def fixture_mirror(root)
      Dir.glob("#{root}/MASTER/test/fixtures/**/bad").filter_map do |bad|
        good = File.join(File.dirname(bad), "good")
        next if Dir.exist?(good)
        Finding.new(id: "fixture_mirror", path: rel(root, bad), line: 0, law: "TRUTHFUL_STATUS",
                    kind: "add", detail: "bad/ fixture has no matching good/",
                    edit: "add the matching good/ fixture", proof: "ruby MASTER/tools/law_fixtures.rb",
                    cost: "small", reversibility: "git revert")
      end
    end

    def generated_banner(root, paths: nil)
      names = %w[AGENTS.md GEMINI.md GLM.md]
      names.select! { |name| paths.include?(File.join(root, name)) } if paths
      names.filter_map do |name|
        f = File.join(root, name)
        next unless File.exist?(f)
        head = File.open(f) { |io| io.read(400) }
        next if head =~ /generated|edit .*not this file/i
        Finding.new(id: "generated_banner", path: name, line: 1, law: "SINGULARITY",
                    kind: "align", detail: "generated pointer lacks an edit-warning banner",
                    edit: "add the generated-file edit warning", proof: "ruby MASTER/tools/polish_lens.rb --json",
                    cost: "trivial", reversibility: "git revert")
      end
    end

    # Compare the generated peers only; CLAUDE.md is the hand-written bootstrap.
    def pointer_symmetry(root, paths: nil)
      names = %w[GEMINI.md GLM.md]
      names.select! { |name| paths.include?(File.join(root, name)) } if paths
      return [] if paths && names.empty?

      counts = %w[GEMINI.md GLM.md].map do |n|
        f = File.join(root, n)
        File.exist?(f) ? File.readlines(f).size : nil
      end.compact
      return [] if counts.uniq.size <= 1
      candidate = (names & %w[GEMINI.md GLM.md]).first || "GEMINI.md"
      [Finding.new(id: "pointer_symmetry", path: candidate, line: 1, law: "PROXIMITY",
                   kind: "align", detail: "generated pointer files differ in length (#{counts.join(", ")})",
                   edit: "make the generated pointers one symmetric line each", proof: "ruby MASTER/tools/polish_lens.rb --json",
                   cost: "trivial", reversibility: "git revert")]
    end

    def doc_links(root, paths: nil)
      findings = []
      docs = Dir.glob("#{root}/{README.md,MASTER/README.md,RAILS/README.md,OPENBSD/RUNBOOK.md,BIZ/README.md}")
      docs.select! { |doc| paths.include?(doc) } if paths
      docs.each do |doc|
        File.readlines(doc).each_with_index do |line, i|
          line.scan(/\]\(([^)#][^)]*)\)/).flatten.each do |link|
            next if link =~ %r{^https?://} || link.start_with?("mailto:")
            target = File.expand_path(link, File.dirname(doc))
            next if File.exist?(target)
            findings << Finding.new(id: "doc_link", path: rel(root, doc), line: i + 1, law: "POLA",
                                    kind: "fix", detail: "broken relative link #{link}",
                                    edit: "fix or remove the link", proof: "ruby MASTER/tools/polish_lens.rb --json",
                                    cost: "trivial", reversibility: "git revert")
          end
        end
      end
      findings
    end
  end
end
