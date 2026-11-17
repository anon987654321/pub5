# frozen_string_literal: true

# The bare law loader: the detect-regex corpus under a bare Ruby, no bundle.
#
# The real machinery (law/definition.rb) is the single source of truth, but it
# pulls lib/master - the whole runtime - through its catalogue bootstrap. The
# bare tier cannot afford that, so it carries the smallest faithful subset of
# the contract: a Builder that captures the same DSL calls, a runner that
# provides the same `finding`/`walk` surface the detectors rely on, and the
# catalogue's own reach policy (languages, path_exclude, lifecycle) applied
# exactly as law/definition.rb applies it. It loads law/lexical.rb verbatim,
# so the detectors that run here are the detectors that run everywhere.
#
# What is deliberately NOT here: semantic and visual laws (they need a model
# or a browser), autofix transforms, the reload machinery. A bare scan names
# its corpus honestly: lexical laws only.

require "yaml"

module Master
  module Agent
    module BareLawLoader
      # A runner is the self a check block executes against: the same surface
      # Master::Review::Scan::Detector gives its blocks, minus the machinery a
      # lexical detector never calls (dedupe keys, genealogy, blast radius).
      class Runner
        def initialize(law_id, severity)
          @id = law_id
          @severity = severity
        end

        def finding(line:, message:, fix: nil, **_rest)
          {
            law: @id,
            line:,
            message:,
            fix: fix || nil,
            severity: @severity,
          }
        end

        # Every node under this one, in source order. The same traversal
        # lib/review/scan/detector.rb runs; copied shape, not imported weight.
        def walk(node, &block)
          return unless node.respond_to?(:child_nodes)

          block.call(node)
          node.child_nodes.compact.each { |child| walk(child, &block) }
        end

        def each_node(node, type, acc = [])
          walk(node) { |child| acc << child if child.is_a?(type) }
          acc
        end

        def scan_lines(code, pattern, message:, fix: nil)
          code.each_line.with_index(1).filter_map do |line, num|
            next unless line.match?(pattern)

            finding(line: num, message:, fix:)
          end
        end

        # Source masking, same shape as lib/review/scan/source_masking.rb.
        # Blanks regions with same-length spaces so line numbers stay true.
        COMMENT_LINE = %r{^[ \t]*(#|//)[^\n]*}
        RULE_FIXTURE_LINE = /^[ \t]*(?:(?:fires|does_not_fire):|(?:bad|good)[ \t]+(?:"|%\(|'))[^\n]*/
        REGEX_LITERAL = %r{(?<![\w)\]])/(?:[^/\\\n]|\\.)+/[mixo]*}

        def without_comment_lines(code) = code.gsub(COMMENT_LINE) { |line| " " * line.length }
        def without_law_fixtures(code) = code.gsub(RULE_FIXTURE_LINE) { |line| " " * line.length }
        def without_regex_literals(code) = code.gsub(REGEX_LITERAL) { |literal| " " * literal.length }

        # The scan:intentional marker exempts the whole comment it sits in,
        # found by walking back to the opener (detector.rb's argument, kept).
        COMMENT_OPENERS = ["#", "//", "/*", "<!--", "<%#"].freeze
        SCAN_MARKER = /scan:\s*intentional\b/

        def without_scan_marker(line)
          text = line.chomp
          marker = text.index(SCAN_MARKER)
          return text unless marker

          opener = COMMENT_OPENERS.filter_map { |token| text.rindex(token, marker) }.max
          return text unless opener

          text[0, opener].rstrip
        end

        # Law files define module-level helpers beside their detectors. A
        # check block that calls one still runs bare: forward to the module
        # the loaded file reopened, exactly as the full runtime does.
        private

        # Ruby's dynamic-dispatch hooks are implementation details, not part
        # of the detector-facing runner API.
        def method_missing(name, *args, **kwargs, &block)
          host = Master::Review::Scan::Laws if defined?(Master::Review::Scan::Laws)
          return host.public_send(name, *args, **kwargs, &block) if host.respond_to?(name)

          super
        end

        def respond_to_missing?(name, include_private = false)
          host = Master::Review::Scan::Laws if defined?(Master::Review::Scan::Laws)
          host.respond_to?(name, include_private) || super
        end
      end

      # Captures the DSL a law file speaks. Tags, fix, bad, good, path and
      # example_path are recorded for the index; check is the detector.
      class Builder
        attr_reader :id, :meta, :checks

        def initialize(id)
          @id = id.to_s
          @meta = {}
          @checks = []
        end

        def tags(*names) = @meta[:tags] = names.flatten.map(&:to_sym)
        def fix(text) = @meta[:fix] = text
        def bad(text) = @meta[:bad] = text
        def good(text) = @meta[:good] = text
        def path(subject) = @meta[:path] = subject
        def example_path(subject) = @meta[:example_path] = subject
        def detect(&block) = @checks << block
        def check(&block) = @checks << block
        def reads_beyond_file(value) = @meta[:reads_beyond_file] = value
        def proved_by(path) = @meta[:proved_by] = path
        def transform(name) = @meta[:transform] = name

        # Semantic and practice laws carry no mechanical detector; the bare
        # tier records them but never invents a verdict for them.
        def ask(_question = nil, *_args) = @meta[:semantic] = true
        def practice(_text = nil, *_args) = @meta[:practice] = true
        def adapters(*) = @meta[:adapters] = true
        def surfaces(*names) = @meta[:surfaces] = names.flatten
        def measures(*names) = @meta[:measures] = names.flatten
        def detector(_name = nil, *_args) = @meta[:external_detector] = true
        def source(text) = @meta[:source] = text
        def severity(text) = @meta[:severity_hint] = text
        def lifecycle(text) = @meta[:lifecycle_hint] = text
        def autofix(text) = @meta[:autofix] = text
      end

      module_function

      # The registry the loaded file's Law.define calls land in. It lives on
      # this module so a reloaded corpus starts empty, and the DSL stub can
      # find it from inside its own singleton.
      def target
        @target ||= {}
      end

      def target=(hash)
        @target = hash
      end

      # Loads one law file verbatim under the captured DSL and returns
      # {id => Builder}. The file's own constants and module functions
      # (PROGRAM_GUARD, matches_mode?, ...) resolve exactly as written.
      def load_file(path)
        builders = {}
        stub_law
        self.target = builders
        load path
        self.target = nil
        builders
      end

      def stub_law
        return if defined?(@bare_law_defined) && @bare_law_defined

        law = Object.const_set(:Law, Module.new)
        law.define_singleton_method(:define) do |id, &block|
          builder = BareLawLoader::Builder.new(id)
          builder.instance_eval(&block)
          BareLawLoader.target[id.to_s] = builder
        end
        # Some law files reopen Law for helper modules; give them a home that
        # tolerates it without dragging in the catalogue machinery.
        law.define_singleton_method(:const_missing) { |name| Object.const_set(name, Module.new) }
        @bare_law_defined = true
      end
    end

    # The corpus as the bare tier may run it, joined with the catalogue's own
    # policy. One row per loadable law.
    class BareCorpus
      attr_reader :laws, :skipped

      def initialize(paths)
        @laws = {}
        @skipped = {}
        paths.each { |path| load_path(path) }
      end

      def load_path(path)
        builders = Master::Agent::BareLawLoader.load_file(path)
        builders.each { |id, builder| register_builder(id, builder) }
      end

      def register_builder(id, builder)
        entry = catalogue_entry(id)
        reason = skip_reason(entry, builder)
        return @skipped[id] = reason if reason

        @laws[id] = { builder:, entry: }
      end

      def skip_reason(entry, builder)
        return "absent from law_catalogue" unless entry
        return "lifecycle retired" if entry["lifecycle"] == "retired"
        return "no lexical detector" unless lexical_detector?(builder)

        nil
      end

      def lexical_detector?(builder)
        builder.checks.any? &&
          !builder.meta[:semantic] &&
          !builder.meta[:practice] &&
          !builder.meta[:external_detector]
      end

      def catalogue_entry(id)
        @entries ||= YAML.safe_load(File.read(laws_path), permitted_classes: [Date, Time], aliases: true)
                         .fetch("law_catalogue").fetch("entries")
        @entries[id] || @entries.find { |name, _e| name.to_s.casecmp?(id) }&.last
      end

      def laws_path
        @laws_path ||= File.expand_path("../../data/laws.yml", __dir__)
      end

      # The catalogue names languages, not extensions; this is the bridge.
      LANGUAGE_EXTENSIONS = {
        "ruby" => %w[.rb .rake .ru], "html" => %w[.html .htm], "css" => %w[.css],
        "scss" => %w[.scss], "javascript" => %w[.js .mjs], "yaml" => %w[.yml .yaml],
        "shell" => %w[.sh .ksh .zsh], "markdown" => %w[.md], "json" => %w[.json],
      }.freeze

      # Reach policy: the catalogue's languages and path_exclude, exactly as
      # law/definition.rb#reach reads them. A law that names no language
      # reaches every file; a law that names some reaches only its own.
      def reaches?(id, path)
        entry = @laws.fetch(id).fetch(:entry)
        languages = Array(entry["languages"]).map(&:to_s)
        if languages.any?
          extensions = languages.flat_map { |l| LANGUAGE_EXTENSIONS.fetch(l, [".#{l}"]) }
          named = extensions.any? { |ext| path.to_s.end_with?(ext) }
          named ||= languages.include?("ruby") && File.basename(path.to_s) == "Rakefile"
          return false unless named
        end

        excluded = Array(entry["path_exclude"])
        excluded.none? { |pattern| path.to_s.match?(Regexp.new(pattern)) }
      rescue Regexp::Error
        true
      end

      def scan_file(path, only: nil)
        src = File.read(path)
        findings = []
        @laws.each do |id, row|
          next if only && !only.include?(id)
          next unless reaches?(id, path)

          runner = BareLawLoader::Runner.new(id, row.fetch(:entry)["severity"])
          row.fetch(:builder).checks.each do |check|
            found = runner.instance_exec(src, path.to_s, &check)
            findings.concat(Array(found).compact)
          rescue StandardError => e
            findings << { law: id, line: 0, message: "detector error: #{e.class}: #{e.message}", severity: "info" }
            break
          end
        end
        findings.each { |f| f[:file] = path.to_s }
        findings.sort_by { |f| [f[:line].to_i, f[:law].to_s] }
      end
    end
  end
end
