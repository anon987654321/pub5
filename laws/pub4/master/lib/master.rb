# frozen_string_literal: true

require "prism"
require "set"
require_relative "../../../../core/core"

# What an imported pub4 Law needs around it to judge the way it judged in
# pub4. It stands where pub4's MASTER/lib/master.rb stood, so the pub4 files
# moved beside it (laws/pub4/master/ mirrors pub4's MASTER/) resolve their
# require_relative paths unchanged. Hand-written; everything else under
# laws/pub4/ is written by `bin/master port-laws`.
#
# Three things carry over:
# - the Master names the bodies reach for: FILE_LANGUAGE_MAP and
#   language_for (pub4 lib/master.rb), ROOT and DATA (laws/pub4/master, so
#   the data files pub4 read sit in its data/), Master.law (law_runtime.yml), and
#   Ground::Swallow, whose log is kept here instead of in a ledger;
# - pub4's file names: a pub4 Law matched paths such as RAILS/ or
#   MASTER/lib/, so it judges each pub5 file under its pub4 name (LAYOUT);
# - pub4's reading and proof (law/definition.rb Proof and Reading): comment
#   blanking by pub4 language, the "-" fixture read whole and again as a
#   real file, and Law.conduct over Law files.
module Master
  ROOT = File.expand_path("..", __dir__).freeze
  REPO_ROOT = Core::ROOT
  DATA = File.join(ROOT, "data").freeze
  LAWS_PATH = File.join(DATA, "laws.yml").freeze
  COUNCIL_PATH = File.join(DATA, "council.yml").freeze
  SEVERITY_RANK = { info: 0, warning: 1, error: 2, critical: 3 }.freeze

  FILE_LANGUAGE_MAP = {
    ".rb" => "ruby", ".rake" => "ruby", ".gemspec" => "ruby", ".ru" => "ruby",
    ".yml" => "yaml", ".yaml" => "yaml", ".json" => "json",
    ".js" => "javascript", ".mjs" => "javascript", ".ts" => "javascript",
    ".jsx" => "javascript", ".tsx" => "javascript",
    ".sh" => "zsh", ".zsh" => "zsh", ".bash" => "zsh", ".ksh" => "zsh", ".md" => "markdown",
    ".html" => "html", ".htm" => "html", ".erb" => "html", ".css" => "css",
    ".scss" => "scss", ".sass" => "scss"
  }.freeze
  NAMED_LANGUAGES = %w[Gemfile Rakefile Guardfile Capfile Brewfile Podfile Vagrantfile config.ru].to_h { |n| [n, "ruby"] }.freeze
  SHEBANG_LANGUAGES = { /\bruby\b/ => "ruby", /\b(?:zsh|bash|ksh|sh)\b/ => "zsh" }.freeze
  RUBY_MAGIC_COMMENT = /\A#\s*(?:frozen_string_literal:|-\*-.*coding)/
  FACE_FRAGMENT = /\Aface\.part\d+\.txt\z/

  # pub4's language_for, reading the first line from the text in hand
  # rather than from disk: a census reads git's bytes, not the work tree.
  def self.language_for(path, text = nil)
    return "javascript" if File.basename(path.to_s).match?(FACE_FRAGMENT)

    FILE_LANGUAGE_MAP[File.extname(path.to_s).downcase] || NAMED_LANGUAGES[File.basename(path.to_s)] ||
      shebang_language(path.to_s, text)
  end

  def self.shebang_language(path, text)
    first = text.to_s[/.*/].to_s.scrub
    return "ruby" if File.extname(path).empty? && first.match?(RUBY_MAGIC_COMMENT)
    return unless first.start_with?("#!")

    SHEBANG_LANGUAGES.find { |pattern, _| pattern.match?(first) }&.last
  end

  def self.laws_runtime = @laws_runtime ||= Core::Registry.yaml(File.join(DATA, "law_runtime.yml")).freeze

  def self.law(section, root: ROOT) = laws_runtime.fetch(section.to_s)

  def self.load_laws(root: ROOT) = laws_runtime

  def self.load_yaml(path, default: nil)
    File.file?(path) ? Core::Registry.yaml(path) : default
  end

  def self.laws_document(root: ROOT) = @laws_document ||= load_yaml(LAWS_PATH, default: {}).freeze

  def self.law_catalogue(root: ROOT) = laws_document.fetch("law_catalogue")

  # pub4's law_entries_in: the normative rows, in source order.
  def self.law_entries(root: ROOT)
    laws_document.filter_map do |id, value|
      next unless value.is_a?(Hash) && value["statement"]
      next unless value.key?("node") || value.key?("root") || value.key?("parent")

      value.merge("id" => id.to_s)
    end
  end

  def self.tokens(root: ROOT) = (load_yaml(File.join(DATA, "tokens.yml"), default: {}) || {})["tokens"] || {}

  def self.design(*path, root: ROOT) = path.empty? ? tokens : tokens.dig(*path.map(&:to_s))

  # pub4 loaded its library by name (Zeitwerk): Master::Design::Scale is
  # lib/design/scale.rb. The port moves each file a Law names that way; this
  # finds it on first use, and a directory with no file of its own becomes
  # a namespace, as Zeitwerk made it.
  module Autoload
    def self.underscore(name) = name.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

    def const_missing(name)
      base = File.join(ROOT, "lib", *self.name.split("::").drop(1).map { |part| Autoload.underscore(part) }, Autoload.underscore(name))
      if File.file?("#{base}.rb")
        require base
        Autoload.spread(self)
        return const_get(name) if const_defined?(name, false)
      elsif File.directory?(base)
        return const_set(name, Module.new.extend(Autoload))
      end
      super
    end

    # Every module under Master answers const_missing the same way.
    def self.spread(mod = Master, seen = {})
      return if seen[mod]

      seen[mod] = true
      mod.extend(Autoload) unless mod.singleton_class.include?(Autoload)
      mod.constants(false).each do |c|
        next unless mod.const_defined?(c, false) && !mod.autoload?(c)

        value = mod.const_get(c, false)
        spread(value, seen) if value.is_a?(Module) && value.name.to_s.start_with?("Master")
      end
    end
  end

  module Ground
    # pub4 logged a swallowed error to its ledger; here it is kept for the
    # census to report.
    module Swallow
      @rows = []

      def self.log(error, **context) = (@rows << context.merge(error: "#{error.class}: #{error.message}")).last

      def self.rows = @rows
    end
  end
end

module Law
  # The CLI, the REPL prompt, the terminal face and dmesg lines print ASCII
  # (pub4 operator, 2026-11-06), so pub4's typographic Laws skip these paths.
  # Matched against a file's pub4 name (Pub4.name).
  TERMINAL_OUTPUT_PATH = %r{
    (?:\A|/)MASTER/(?:bin|lib|tools|checks|law|data|plugins|completions|test)/ |
    (?:\A|/)(?:OPENBSD|STUDIO)/(?!.*\.(?:md|markdown|tex|html)\z) |
    (?:\A|/)bin/ |
    \.(?:sh|ksh|zsh)\z
  }x.freeze

  def self.terminal_output?(path) = path.to_s.match?(TERMINAL_OUTPUT_PATH)

  module Pub4
    # pub5 tree => the pub4 tree the same files came from. pub4 Laws name
    # RAILS/, MASTER/lib/ and BPLANS/ in their paths and exemptions; a pub5
    # file is judged under the name it had there.
    LAYOUT = {
      "rails/" => "RAILS/", "openbsd/" => "OPENBSD/", "studio/" => "STUDIO/", "bplans/" => "BPLANS/",
      "master/" => "MASTER/", "core/" => "MASTER/lib/", "laws/" => "MASTER/law/", "registry/" => "MASTER/data/",
      "tools/" => "MASTER/tools/", "test/" => "MASTER/test/"
    }.freeze

    def self.name(path)
      path = path.to_s
      from, to = LAYOUT.find { |prefix, _| path.start_with?(prefix) }
      from ? to + path.delete_prefix(from) : path
    end

    AUTOFIX = %i[never review automatic].freeze
    SEVERITY = { "warn" => :warn, "warning" => :warning, "error" => :error, "info" => :info, "veto" => :veto }.freeze
    INTENTIONAL = /scan:\s*intentional\b/
    LANGUAGE_COMMENT_LEADERS = {
      "ruby" => ["#"], "yaml" => ["#"], "zsh" => ["#"], "javascript" => ["//", "/*"],
      "css" => ["/*"], "scss" => ["//", "/*"], "html" => ["<!--"]
    }.freeze
    EXTENSION_COMMENT_LEADERS = { ".erb" => ["<%#"] }.freeze
    COMMENT_SPANS = { ".erb" => ["<%#", "%" + ">"], ".css" => ["/*", "*/"], ".scss" => ["/*", "*/"] }.freeze
    REALISTIC_EXTENSION = {
      ".rb" => "ruby", ".js" => "javascript", ".scss" => "scss", ".css" => "css",
      ".html" => "html", ".yml" => "yaml", ".sh" => "zsh", ".md" => "markdown", ".json" => "json"
    }.freeze
    PROOF_PATHS = {
      "ruby" => "/repo/app/models/example.rb", "zsh" => "/repo/bin/example.sh",
      "scss" => "/repo/app/assets/stylesheets/_example.scss", "css" => "/repo/app/assets/stylesheets/example.css",
      "html" => "/repo/app/views/example.html.erb",
      "javascript" => "/repo/app/javascript/controllers/example_controller.js"
    }.freeze
    TREE_SURFACES = %i[repository_tree directories file_names paths].freeze

    def self.comment_leaders(file)
      LANGUAGE_COMMENT_LEADERS.fetch(Master.language_for(file), []) +
        EXTENSION_COMMENT_LEADERS.fetch(File.extname(file.to_s).downcase, [])
    end

    # pub4's Law.conduct: a Law file carries the pattern it forbids in its
    # detector, fix text and fixtures. Those lines are evidence, not conduct,
    # so they are blanked (line numbers kept) before a Law judges laws/.
    def self.conduct(text)
      fence = nil
      block_end = nil
      text.each_line.map do |line|
        if fence
          fence = nil if line.strip == fence
          next "#\n"
        end
        if block_end
          block_end = nil if line == block_end
          next "#\n"
        end
        if (indent = line[/^(\s*)(?:detect|check|scan_lines)\s+do\b/, 1])
          block_end = "#{indent}end\n"
          next "#\n"
        end

        fence = line[/^\s*(?:bad|good|ask|practice)\s+<<~["']?(\w+)["']?/, 1]
        line.match?(/^\s*(?:source|detect|check|ask|practice|fix|bad|good)\b/) ? "#\n" : line
      end.join
    end

    # One pub4 adapter, called the way pub4 called it.
    def self.call_adapter(adapter, runner, input, file)
      runner.instance_exec(*(adapter.tree? ? [input] : [input, file]), &adapter.check)
    end

    def self.adapter_proof_file(adapter)
      adapter.example_path || PROOF_PATHS.fetch(adapter.languages.first.to_s, PROOF_PATHS.fetch("ruby"))
    end

    Hit = Data.define(:line, :text, :message)

    # A pub4 Law::Definition rebuilt over a pub5 Definition: the same member
    # readers, its policy from the registry row (pub4 severity, mode and
    # autofix, catalogue languages and path_exclude), and pub4's Proof and
    # Reading, so a body that ran in pub4 runs here unchanged.
    class Subject
      MEMBERS = %i[id source scope absent detect check detector ask practice fix bad good reads_comments tags
                   example_path reads_beyond_file transform proved_by measures adapters path].freeze
      MEMBERS.each { |member| define_method(member) { @options[member] } }

      attr_reader :severity, :mode, :autofix, :languages, :path_exclude, :lifecycle

      def initialize(options, row)
        Master::Autoload.spread
        @options = options
        origin = row.fetch("pub4", {})
        scope = row.fetch("scope", {})
        @severity = SEVERITY.fetch(origin.fetch("severity", "warning").to_s, :warning)
        @mode = origin.fetch("mode", "violation").to_sym
        @autofix = row.fetch("autofix", "review").to_sym
        @lifecycle = :advisory
        @languages = Array(scope["languages"]).map(&:to_s) | Array(options[:languages]).map(&:to_s)
        excluded = Array(scope["path_exclude"])
        @path_exclude = excluded.empty? ? nil : Regexp.union(excluded.map { |s| Regexp.new(s) })
      end

      def surfaces = nil
      def law_scope = :domain
      def semantic? = !ask.nil?
      def model_detector? = detector ? detector.method_defined?(:set_agent) : false
      def main_detector? = detect || check || (detector && !model_detector?) ? true : false
      def scannable? = main_detector? || file_adapters.any?
      def file_adapters = adapters.reject(&:tree?)
      def tree_adapters = adapters.select(&:tree?)

      def applies?(file, language)
        return false if path && !(path.is_a?(Regexp) ? file.match?(path) : file.include?(path))
        return false if path_exclude && file.match?(path_exclude)

        main_reads?(language) || file_adapters.any? { |a| language && (a.languages.empty? || a.languages.include?(language)) }
      end

      def main_reads?(language) = languages.empty? || (language && languages.include?(language.to_s)) ? true : false

      # pub4 Definition#scan: the Law's own detector where its languages
      # reach the file, then each file adapter that reads its language.
      def scan(text, file:, language: nil)
        language = file == "-" ? nil : language || Master.language_for(file, text)
        hits = main_detector? && (language.nil? || main_reads?(language)) ? scan_main(text, file) : []
        file_adapters.each do |a|
          hits += run_adapter(a, text, file:) if language && (a.languages.empty? || a.languages.include?(language))
        end
        hits
      end

      def scan_tree(paths) = tree_adapters.flat_map { |a| run_adapter(a, paths) }

      def proof_path = example_path || PROOF_PATHS.fetch(languages.first.to_s, PROOF_PATHS.fetch("ruby"))
      def proof_file = example_path || check || detector ? proof_path : "-"

      # pub4 Proof#prove!: fixtures (also as a real file for a "-" proof),
      # each adapter on its own surface, the autofix policy and the reach.
      def prove!
        if proved_by then prove_named_test!
        elsif main_detector? then prove_fixtures!
        end
        adapters.each { |a| prove_adapter!(a) }
        prove_policy!
        prove_reach!
        self
      end

      private

      def fail!(reason) = raise(Invalid, "#{id}: #{reason}")

      def prove_named_test!
        # pub4's semantics (MASTER/law/definition.rb): a law proved by a named
        # test holds when that test file exists in the tree it ships with. The
        # named suite is pub5's own here (test/laws/), so the path resolves
        # against this checkout's root, not the imported lib's own directory.
        fail!("proved_by #{proved_by} does not exist") unless File.file?(File.join(Core::ROOT, proved_by.to_s))
      end

      def prove_fixtures!
        at = proof_file == "-" ? "" : " at #{proof_file}"
        fail!("bad fixture not flagged#{at}") if scan_main(bad, proof_file).empty?
        fail!("good fixture flagged#{at}") unless scan_main(good, proof_file).empty?

        prove_as_real_file! if proof_file == "-"
      end

      def prove_adapter!(adapter)
        where = "#{adapter.surfaces.join('+')} adapter"
        fail!("#{where} bad example not flagged") if run_adapter(adapter, adapter.bad).empty?
        fail!("#{where} good example flagged") unless run_adapter(adapter, adapter.good).empty?
      end

      def prove_policy!
        fail!("unknown autofix policy #{autofix.inspect}") unless AUTOFIX.include?(autofix)
        fail!("automatic autofix requires a deterministic detector") if autofix == :automatic && !scannable?
      end

      def prove_reach!
        unreachable = languages - Master::FILE_LANGUAGE_MAP.values.uniq
        fail!("declares language(s) #{unreachable.join(', ')} that FILE_LANGUAGE_MAP never produces") if unreachable.any?
      end

      def prove_as_real_file!
        extensions = languages.empty? ? [REALISTIC_EXTENSION.keys.first] : REALISTIC_EXTENSION.filter_map { |e, l| e if languages.include?(l) }
        extensions.each do |extension|
          as_file = "fixture#{extension}"
          if scan(bad, file: as_file).empty?
            fail!("bad fixture flagged on \"-\" but not on #{extension} - considered_text blanks its subject first (set reads_comments?)")
          end
          fail!("good fixture clean on \"-\" but flagged on #{extension}") unless scan(good, file: as_file).empty?
        end
      end

      def runner = Master::Review::Scan::Detector.new.bind(self)

      def scan_main(text, file)
        return scan_check(text, file) if check
        return law_hits(detector.build(self).check(text, path: file), text.lines) if detector

        scope == :file ? scan_file(text, file) : scan_lines(text, file)
      end

      def scan_file(text, file)
        return [] if absent && text.match?(absent)
        return [] unless detect.call(considered_text(text, file))

        [Hit.new(1, text[/.*/].to_s, nil)]
      end

      def scan_check(text, file)
        return [] if absent && text.match?(absent)

        law_hits(runner.instance_exec(text, file, &check), text.lines)
      end

      def run_adapter(adapter, input, file: nil)
        return Array(Pub4.call_adapter(adapter, runner, input, nil)).map { |h| hit(h, []) } if adapter.tree?

        file ||= Pub4.adapter_proof_file(adapter)
        law_hits(Pub4.call_adapter(adapter, runner, input, file), input.lines)
      end

      def law_hits(hits, lines) = Array(hits).map { |h| hit(h, lines) }

      def hit(raw, lines)
        line = Master::Review::Scan::Finding.read(raw, :line).to_i
        Hit.new(line, lines[line - 1].to_s.chomp, Master::Review::Scan::Finding.read(raw, :message))
      end

      def scan_lines(text, file)
        leaders = reads_comments ? [] : Pub4.comment_leaders(file)
        continued = reads_comments ? [] : continued_comment_lines(text, file)
        text.each_line.with_index.filter_map do |line, index|
          next if line.match?(INTENTIONAL)
          next if continued.include?(index) || leaders.any? { |leader| line.lstrip.start_with?(leader) }

          Hit.new(index + 1, line.chomp, nil) if detect.call(line)
        end
      end

      def considered_text(text, file)
        leaders = reads_comments ? [] : Pub4.comment_leaders(file)
        continued = reads_comments ? [] : continued_comment_lines(text, file)
        return text if leaders.empty? && continued.empty? && !text.include?("scan:")

        text.each_line.with_index.map do |line, index|
          next "\n" if continued.include?(index)
          next line if index.zero? && line.start_with?("#!")

          skip = leaders.any? { |leader| line.lstrip.start_with?(leader) } || line.match?(INTENTIONAL)
          skip ? "\n" : line
        end.join
      end

      def continued_comment_lines(text, file)
        opener, closer = COMMENT_SPANS[File.extname(file.to_s)]
        return [] unless opener && text.include?(opener)

        inside = false
        text.each_line.with_index.filter_map do |line, index|
          opened = inside
          unless inside
            open_at = line.rindex(opener)
            inside = true if open_at && !line[open_at..].include?(closer)
          end
          if inside && line.include?(closer)
            inside = false
            next opened ? index : nil
          end
          index if inside && opened
        end
      end
    end
  end
end

require_relative "review/scan/detector"
Master::Autoload.spread
