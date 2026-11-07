# frozen_string_literal: true

require_relative "../core/core"

# The Law engine. A Law is two halves that must agree:
#
# - its policy row in registry/laws.yml: statement, kind, severity, lifecycle,
#   autofix, enacted date and census (the one place policy lives), and
# - its Ruby in laws/<id>.rb: `Law.define(:ID) { ... }` with a detector and
#   bad/good fixtures, proved when the file loads.
#
# The DSL accepts every word pub4's Law::Builder accepted (MASTER/law/
# definition.rb MEMBERS), so P2 can import all of pub4's Laws mechanically:
# each enters as advisory and is promoted to enforced only when its fixtures
# prove at load and a census over the real tree shows at most 5% false
# positives, ratified by the operator. pub4's checks, ratchets and house lint
# are kinds of Law here, and operator directives are `conduct` Laws.
module Law
  KINDS = %w[lexical structural rendered runtime ratchet check lint semantic conduct].freeze
  LIFECYCLES = %w[advisory enforced retired].freeze
  SEVERITIES = %w[info warning error critical].freeze
  AUTOFIX = %w[never review automatic].freeze
  MAX_FALSE_POSITIVE_RATE = 0.05
  MIN_ASK_AGREEMENT = 0.80
  # An autofix reaching more files than this publishes a dry-run census first.
  BULK_AUTOFIX_FILES = 20
  POLICY_WORDS = %i[severity mode lifecycle autofix statement kind enacted].freeze

  LANGUAGES = {
    "ruby" => %w[.rb .rake .ru .gemspec], "yaml" => %w[.yml .yaml], "json" => %w[.json],
    "erb" => %w[.erb], "javascript" => %w[.js .mjs], "css" => %w[.css .scss], "shell" => %w[.sh .zsh],
    "markdown" => %w[.md], "html" => %w[.html]
  }.freeze
  COMMENT = { "ruby" => /\A\s*#/, "yaml" => /\A\s*#/, "shell" => /\A\s*#/, "javascript" => %r{\A\s*//},
              "css" => %r{\A\s*(/\*|\*|//)}, "erb" => /\A\s*<%#/ }.freeze
  INTENTIONAL = /scan:\s*intentional\b/

  Finding = Data.define(:law, :file, :line, :text, :message) do
    def to_s = "#{file}:#{line}: #{law}: #{message || text.strip}"
  end

  class Invalid < StandardError; end

  @laws = {}

  class << self
    # Builds and proves one Law against its registry row (the row being
    # loaded, or none outside load!). A Law whose row records it as broken is
    # kept, marked with its failure, instead of refusing the load.
    def define(id, &block)
      id = id.to_sym
      raise Invalid, "#{id}: defined twice" if @laws.key?(id)

      row = @rows ? @rows.fetch(id.to_s, {}) : {}
      @laws[id] = begin
        builder = Builder.new(id)
        builder.instance_eval(&block)
        builder.build(row).prove!
      rescue StandardError => e
        raise unless row["broken"]

        Definition.broken(id, row, e)
      end
    end

    def all = @laws.values

    def [](id) = @laws.fetch(id.to_sym)

    def reset! = @laws.clear

    # A file's language by extension; an extensionless script by its shebang
    # (bin/master, .githooks/pre-commit) when its text is at hand.
    def language(path, text = nil)
      ext = File.extname(path)
      return "ruby" if ext.empty? && text&.start_with?("#!/usr/bin/env ruby")

      LANGUAGES.find { |_, exts| exts.include?(ext) }&.first
    end

    # Loads every laws/*.rb and reconciles it with the index: a Law without a
    # row, a row without a Law, a bad row, or an enforced Law that never
    # qualified, each refuses the load.
    def load!(dir: File.join(Core::ROOT, "laws"), index: Core::Registry.load(:laws))
      @laws.clear
      rows = index.fetch("laws")
      errors = load_files(dir, rows)
      errors += (rows.keys - @laws.keys.map(&:to_s)).map { |id| "#{id}: indexed but never defined" }
      errors += (@laws.keys.map(&:to_s) - rows.keys).map { |id| "#{id}: defined but not indexed in registry/laws.yml" }
      rows.each { |id, row| errors += Policy.problems(id, row, @laws[id.to_sym]) }
      raise Invalid, errors.join("\n") if errors.any?

      rows.each { |id, row| @laws[id.to_sym]&.policy = row }
      all
    end

    # Every Law file: laws/*.rb, written in pub5, and laws/pub4/*.rb,
    # imported from pub4 by `bin/master port-laws`.
    def files(dir) = (Dir[File.join(dir, "*.rb")] + Dir[File.join(dir, "pub4", "*.rb")]).sort - [__FILE__]

    # Loads each file with its rows in reach of define. A file that fails
    # before it defines its Law (a missing constant in shared code) is kept
    # as broken when its row says so, and refuses the load otherwise.
    def load_files(dir, rows)
      @rows = rows
      files(dir).filter_map do |file|
        Kernel.load(file)
        nil
      rescue StandardError, ScriptError => e
        relative = "laws/#{file.delete_prefix("#{dir}/")}"
        id, row = rows.find { |_, r| r["file"] == relative }
        next "#{relative}: #{e.class}: #{e.message}" unless row&.fetch("broken", nil)

        @laws[id.to_sym] ||= Definition.broken(id.to_sym, row, e)
        nil
      end
    ensure
      @rows = nil
    end

    # What `bin/master port-laws` records: each file loaded as if its row
    # said broken, so every failure is caught and named instead of raised.
    # Answers id => failure, nil where the Law proved.
    def measure(paths, rows)
      @laws.clear
      @rows = rows.transform_values { |row| row.merge("broken" => "measuring") }
      paths.each_with_object({}) do |path, result|
        before = @laws.keys
        begin
          Kernel.load(path)
        rescue StandardError, ScriptError => e
          result[File.basename(path, ".rb").upcase] = "#{e.class}: #{e.message}"
        end
        (@laws.keys - before).each { |id| result[id.to_s] = @laws[id].broken }
      end
    ensure
      @rows = nil
    end

    def enforced = all.select(&:enforced?)

    def scan(paths, root: Core::ROOT, laws: all)
      paths.flat_map do |path|
        full = File.expand_path(path, root)
        next [] unless File.file?(full)

        text = File.read(full, encoding: "UTF-8", invalid: :replace, undef: :replace)
        laws.flat_map { |law| law.scan(text, path) }
      end
    end
  end

  # What a policy row must say before its Law may load, and what an enforced
  # row must have measured.
  module Policy
    module_function

    def problems(id, row, law)
      errors = []
      errors << "#{id}: kind #{row['kind'].inspect} not in #{KINDS.join(', ')}" unless KINDS.include?(row["kind"])
      errors << "#{id}: lifecycle #{row['lifecycle'].inspect}" unless LIFECYCLES.include?(row["lifecycle"])
      errors << "#{id}: severity #{row['severity'].inspect}" unless SEVERITIES.include?(row["severity"])
      errors << "#{id}: autofix #{row['autofix'].inspect}" unless AUTOFIX.include?(row["autofix"])
      files = ["laws/#{id.downcase}.rb", "laws/pub4/#{id.downcase}.rb"]
      errors << "#{id}: file must be #{files.join(' or ')}" if law && !files.include?(row["file"])
      errors << "#{id}: marked broken but its fixtures prove; clear broken" if law && row["broken"] && !law.broken
      errors + (row["lifecycle"] == "enforced" ? promotion_problems(id, row, law) : [])
    end

    # Enforced means: deterministic detector proved at load (or a model judge
    # with measured agreement), a census over the real tree, a false-positive
    # rate of at most 5% on a sample, and the operator's ratification.
    def promotion_problems(id, row, law)
      return ["#{id}: broken (#{row['broken']}); a broken Law cannot be enforced"] if row["broken"]
      return ["#{id}: unported (#{row['unported']}); its detector awaits a hand port"] if row["unported"]

      census = row["census"] or return ["#{id}: enforced without a census"]
      errors = []
      errors << "#{id}: a conduct Law with no detector stays advisory" if law && !law.deterministic? && !law.semantic?
      sampled = census.fetch("sampled", 0).to_i
      findings = census.fetch("findings", 0).to_i
      errors << "#{id}: census sampled #{sampled} of #{findings} findings, needs #{[findings, 20].min}" if sampled < [findings, 20].min
      rate = sampled.zero? ? 0.0 : census.fetch("false_positives", 0).to_f / sampled
      errors << "#{id}: false-positive rate #{(rate * 100).round(1)}% exceeds 5%" if rate > MAX_FALSE_POSITIVE_RATE
      if law&.semantic? && !law.deterministic? && census.fetch("agreement", 0).to_f < MIN_ASK_AGREEMENT
        errors << "#{id}: model-judged Law needs measured agreement >= 80%"
      end
      errors << "#{id}: enforced without operator ratification" unless census["ratified_by"] == "operator"
      errors
    end
  end
end

require_relative "engine/definition"
require_relative "engine/builder"
require_relative "engine/check_runner"
