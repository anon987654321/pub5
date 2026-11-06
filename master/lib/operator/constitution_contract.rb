# frozen_string_literal: true

require "yaml"

module Operator
  class ConstitutionContract
    ROOT = File.expand_path("../../..", __dir__)
    REQUIRED = %w\[
      master/data/soul.yml
      master/data/laws.yml
      master/lib/soul.rb
      master/data/project_context.yml
      master/bin/master
      master/lib/review/scan
      master/law/definition.rb
      rails/CLAUDE.md
      rails/__shared/design_tokens.yml
      openbsd/CLAUDE.md
      openbsd/PATH_OWNERSHIP.yml
      openbsd/data/operator.yml
    ].freeze

    Result = Data.define(:issues) do
      def clean? = issues.empty?
    end

    def initialize(root: ROOT)
      @root = root
    end

    def check
      issues = required_paths
      require File.join(@root, "master", "lib", "master") unless defined?(Master::ROOT)
      soul = load_yaml("master/data/soul.yml")
      laws = load_yaml("master/data/laws.yml")
      issues << "soul: golden Law reference missing or changed" unless soul.dig("references", "golden_law") == "PRESERVE_FIRST"
      issues << "soul: no canonical sacred paths declared" unless Master::Soul.sacred_paths(root: File.join(@root, "master")).any?
      begin
        Master::Soul.load!(root: File.join(@root, "master"))
      rescue StandardError => e
        issues << "soul: canonical Ruby identity failed integrity verification (#{e.class})"
      end
      tokens = load_yaml("master/data/tokens.yml")
      issues << "rules: missing design tokens" unless tokens["tokens"].is_a?(Hash)
      begin
        Master::FlatLawCatalogue.validate!(laws)
        nodes = Master::FlatLawCatalogue.entries(laws).select { |entry| entry["node"] }
        issues << "laws: expected nine ordered invariant nodes" unless nodes.size == 9
      rescue StandardError => e
        issues << "laws: canonical constitution failed validation (#{e.class}: #{e.message})"
      end
      # The typographic Laws credit their source in the Law file that defines them.
      laws = Dir.glob(File.join(@root, "master", "law", "*.rb"))
      issues << "rules: no Bringhurst reference" unless laws.any? { |file| File.read(file).include?("Bringhurst") }
      issues.concat(law_issues)
      issues.concat(law_catalogue_issues)
      issues.concat(tree_authority_issues)
      Result.new(issues.uniq.freeze)
    rescue StandardError => e
      Result.new((issues + ["constitution: #{e.class}: #{e.message}"]).uniq.freeze)
    end

    private

    def required_paths
      REQUIRED.filter_map do |relative|
        relative unless File.exist?(File.join(@root, relative))
      end
    end

    def load_yaml(relative)
      YAML.safe_load_file(File.join(@root, relative), aliases: true) || {}
    end

    def law_issues
      require File.join(@root, "master", "law", "definition")
      ::Law.load_all(File.join(@root, "master", "law")) if ::Law.definitions.empty?
      ::Law.definitions.empty? ? ["law: no executable laws loaded"] : []
    rescue StandardError => e
      ["law: #{e.class}: #{e.message}"]
    end

    def law_catalogue_issues
      require File.join(@root, "master", "lib", "master") unless defined?(Master::ROOT)
      require File.join(@root, "master", "lib", "review", "scan", "law_registry_audit")
      report = Master::Review::Scan::LawRegistryAudit.new(root: File.join(@root, "master")).call
      report.assert_catalogue_integrity!
      []
    rescue StandardError => e
      ["law: catalogue integrity failed - #{e.class}: #{e.message}"]
    end

    def tree_authority_issues
      issues = []
      rails_tokens = File.join(@root, "rails/__shared/design_tokens.yml")
      if File.file?(rails_tokens)
        header = File.read(rails_tokens).lines.first(2).join
        issues << "rails: generated design tokens lost master source marker" unless header.include?("master/data/tokens.yml")
      end
      issues << "openbsd: missing operator recipe authority" unless File.file?(File.join(@root, "openbsd/data/operator.yml"))
      issues
    end
  end
end
