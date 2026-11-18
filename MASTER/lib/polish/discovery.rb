# frozen_string_literal: true

# Polish::Discovery
# Scans the repository (and TraceStore signals) for polishing opportunities.
# Designed to be called from /fix and from continuous background loops.
# Never invents product work; only surfaces refinement of what already exists.

require_relative "opportunity"
require_relative "../stigmergy/trace_store"

module Polish
  class Discovery
    def initialize(repo_root:, trace_store: nil)
      @repo_root = File.expand_path(repo_root)
      @traces = trace_store || Stigmergy::TraceStore.new
    end

    # Returns Array<Polish::Opportunity>
    def scan(surfaces: :all, limit: 200)
      opportunities = []
      opportunities.concat(scan_structure) if surfaces == :all || surfaces.include?(:structure)
      opportunities.concat(scan_documentation) if surfaces == :all || surfaces.include?(:documentation)
      opportunities.concat(scan_naming) if surfaces == :all || surfaces.include?(:naming)
      opportunities.concat(scan_cli) if surfaces == :all || surfaces.include?(:cli)
      opportunities.concat(scan_traces) if surfaces == :all || surfaces.include?(:stigmergy)
      opportunities.concat(scan_principle_signals) if surfaces == :all || surfaces.include?(:principle)
      opportunities.first(limit)
    end

    def scan_and_emit!(**kwargs)
      found = scan(**kwargs)
      found.each do |opp|
        @traces.emit(
          kind: :polish,
          subject: opp.surface,
          payload: opp.to_h,
          strength: severity_to_strength(opp.severity),
          source: "polish.discovery"
        )
      end
      found
    end

    private

    def scan_structure
      opps = []
      # Deep or inconsistently named directories
      Dir.glob(File.join(@repo_root, "**/*")).select { |p| File.directory?(p) }.each do |dir|
        rel = rel(dir)
        depth = rel.split("/").size
        if depth > 6
          opps << Opportunity.new(
            category: "structure",
            severity: "minor",
            title: "Deep directory nesting: #{rel}",
            rationale: "Depth > 6 increases navigation cost and violates the preferred tree contract.",
            surface: rel,
            suggested_action: "Collapse or re-home under a shallower parent; update PATH_OWNERSHIP.yml."
          )
        end
        base = File.basename(dir)
        if base =~ /[A-Z]/ && base !~ /\A[A-Z][a-z]+\z/ && !%w[MASTER BIZ RAILS OPENBSD STUDIO].include?(base)
          opps << Opportunity.new(
            category: "naming",
            severity: "cosmetic",
            title: "Mixed-case directory name: #{rel}",
            rationale: "Prefer kebab-case or the established top-level proper names only.",
            surface: rel,
            suggested_action: "Rename to kebab-case and fix all references."
          )
        end
      end
      opps
    end

    def scan_documentation
      opps = []
      Dir.glob(File.join(@repo_root, "**/*.md")).each do |path|
        next if path.include?("/vendor/") || path.include?("/node_modules/")
        rel = rel(path)
        content = File.read(path, encoding: "UTF-8") rescue next
        if content.lines.size > 200 && !content.match?(/^## Table of contents|^## TOC/i)
          opps << Opportunity.new(
            category: "documentation",
            severity: "minor",
            title: "Long document without TOC: #{rel}",
            rationale: "Documents > 200 lines benefit from a generated or hand-maintained table of contents.",
            surface: rel,
            suggested_action: "Add a TOC section or generate one in the docs pipeline."
          )
        end
        if content.match?(/\bTODO\b|\bFIXME\b|\bXXX\b/)
          opps << Opportunity.new(
            category: "documentation",
            severity: "moderate",
            title: "Residual TODO/FIXME marker in #{rel}",
            rationale: "Backlog is assumed clear; residual markers are polish debt or dead text.",
            surface: rel,
            suggested_action: "Convert to a tracked polish opportunity or delete the marker."
          )
        end
        unless content.match?(/\A\s*#|\A\s*---|\A\s*[A-Z]/)
          opps << Opportunity.new(
            category: "documentation",
            severity: "cosmetic",
            title: "Document lacks clear opening purpose line: #{rel}",
            rationale: "Every public Markdown file should open with a one-sentence purpose.",
            surface: rel,
            suggested_action: "Add a single-sentence purpose immediately after the title."
          )
        end
      end
      opps
    end

    def scan_naming
      opps = []
      Dir.glob(File.join(@repo_root, "**/*.{rb,yml,md,sh}")).each do |path|
        next if path.include?("/vendor/")
        rel = rel(path)
        base = File.basename(path)
        if base.include?(" ") || base.include?("--")
          opps << Opportunity.new(
            category: "naming",
            severity: "minor",
            title: "Awkward filename: #{rel}",
            rationale: "Spaces or double-hyphens in filenames create friction for tools and humans.",
            surface: rel,
            suggested_action: "Rename to clean kebab-case or snake_case."
          )
        end
      end
      opps
    end

    def scan_cli
      opps = []
      bin_dir = File.join(@repo_root, "MASTER", "bin")
      return opps unless File.directory?(bin_dir)
      Dir.children(bin_dir).each do |name|
        path = File.join(bin_dir, name)
        next unless File.file?(path)
        rel = rel(path)
        content = File.read(path, encoding: "UTF-8") rescue next
        unless content.match?(/--help|Usage:|help\s*=/)
          opps << Opportunity.new(
            category: "cli",
            severity: "moderate",
            title: "CLI entry lacks visible help: #{rel}",
            rationale: "Every bin/* command should respond usefully to --help.",
            surface: rel,
            suggested_action: "Add a help path that prints purpose, flags, and one example."
          )
        end
      end
      opps
    end

    def scan_traces
      opps = []
      weak = @traces.read_active(min_strength: 0.0).select { |t| t[:strength].to_f < 0.3 }
      if weak.size > 20
        opps << Opportunity.new(
          category: "stigmergy",
          severity: "minor",
          title: "Large number of low-strength traces (#{weak.size})",
          rationale: "Stigmergic signal should decay or be archived; noise reduces usefulness.",
          surface: "data/traces",
          suggested_action: "Run TraceStore#decay_all and review archive policy."
        )
      end
      opps
    end

    def scan_principle_signals
      # Placeholder for future metric-driven principle scanners (DRY/KISS/SOLID/POLA).
      # Real implementation will consume RuboCop/Reek/custom cops and TraceStore metrics.
      []
    end

    def rel(path)
      path.sub(%r{\A#{Regexp.escape(@repo_root)}/?}, "")
    end

    def severity_to_strength(sev)
      { "cosmetic" => 0.4, "minor" => 0.8, "moderate" => 1.3, "substantial" => 2.0 }[sev] || 0.8
    end
  end
end
