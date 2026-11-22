# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "prism"
require "timeout"

require_relative "law_timing"
require_relative "file_lock"
require_relative "unmodelled_tier"
require_relative "finding_cache"
require_relative "source_override"
require_relative "../check_focus"
require_relative "../../review/scan/semantic_fingerprint"
require_relative "../../review/scan/law_health"
require_relative "../../trace/dmesg"
# The re-opened parts of this class, one responsibility each; every path is
# listed in data/autoload.yml under autoload.reopens_a_constant_defined_elsewhere.
require_relative "file_processor/progress"
require_relative "file_processor/semantic_tier"

module Master
  module Fix
    module Scan
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze
        include FileLock
        include UnmodelledTier

        LOCK_DIR = ".constitutional_locks"
        LOCK_TIMEOUT = 30
        MAX_FILE_BYTES = 10 * 1024 * 1024
        MAX_LINES = 10_000
        STYLE_EXTENSIONS = %w[.css .scss].freeze
        STYLE_MAX_LINES = 12_000
        STRUCTURED_DATA_EXTENSIONS = %w[.json .yml .yaml].freeze
        STRUCTURED_DATA_MAX_LINES = 20_000
        OUTSIDE_SAMPLE = "clean file, outside sample"
        UNCHANGED = "unchanged since its last semantic read"
        DEFERRED = "put off behind the pass's mechanical repairs"
        OVER_BUDGET = "past the pass's semantic budget"
        # Model reads, kept apart from the deterministic findings so each is keyed on its own law set.
        SEMANTIC_DIR = File.join(".master", "semantic_findings")

        # The longest file each kind of source may be before a scan refuses it.
        def self.max_lines_for(path)
          extension = File.extname(path.to_s).downcase
          return STYLE_MAX_LINES if STYLE_EXTENSIONS.include?(extension)
          return STRUCTURED_DATA_MAX_LINES if STRUCTURED_DATA_EXTENSIONS.include?(extension)

          MAX_LINES
        end

        def initialize(event_bus: nil, skip_semantic: false, root: Master::ROOT, cache_root: Master::ROOT)
          @root = Master.master_root(root:)
          @bus = event_bus
          init_semantic_tier_state(skip_semantic:, cache_root:)
          @finding_cache = FindingCache.new(root: cache_root)
          @ast_mutex = Mutex.new
          @ast_assessments = {}
          init_progress_state
        end

        # Per-file parser receipts let the assessment matrix distinguish a real
        # syntax-tree reading from a scanner pass that silently fell back to text.
        def ast_assessments
          @ast_mutex.synchronize { @ast_assessments.dup }
        end

        def reset_ast_assessments!
          @ast_mutex.synchronize { @ast_assessments.clear }
          self
        end

        def call(path:, depth:, laws:)
          with_file_lock(path) { measure(path:, depth:, laws:) }
        rescue LockTimeout => e
          unmeasured(path, e)
        rescue StandardError => e
          @bus&.publish("scan:error", path:, error: e.message)
          Result.err("scan failed: #{e.class}: #{e.message} at #{e.backtrace&.first}", category: :infrastructure)
        end

        private

        def measure(path:, depth:, laws:)
          read = read_file(path)
          return read if read.err?

          code = read.value!
          ast = parse_ruby(code, path)
          record_ast_assessment(path:, code:, ast:) if Master.language_for(path) == "ruby"
          fingerprint = Master::Review::Scan::SemanticFingerprint.for(code)
          findings = annotate_findings(apply_laws(code:, ast:, path:, law_set: laws), fingerprint:)
          publish_scan_result(path:, depth:, findings:)
          Result.ok(findings)
        end

        # Per-file parser receipts let the assessment matrix distinguish a real
        # syntax-tree reading from a scanner pass that silently fell back to text.
        def record_ast_assessment(path:, code:, ast:)
          status = ast ? "assessed" : "inconclusive"
          row = {
            "status" => status,
            "sha256" => Digest::SHA256.hexdigest(code),
            "reason" => ast ? nil : "Prism did not produce a syntax tree for the current Ruby source",
          }.freeze
          @ast_mutex.synchronize { @ast_assessments[File.expand_path(path)] = row }
          @bus&.publish(
            "scan:ast_assessment",
            path: File.expand_path(path),
            status:,
            sha256: row["sha256"],
            reason: row["reason"],
          )
        end

        # A path with a SourceOverride is judged by that text, not by the disk.
        def read_file(path)
          read = SourceOverride.read(path, max_bytes: MAX_FILE_BYTES) || read_disk(path)
          return read if read.err?

          code = read.value!.scrub
          line_count = code.count("\n")
          line_count += 1 unless code.empty? || code.end_with?("\n")
          return Result.err("file too long: #{path}", category: :validation) if line_count > self.class.max_lines_for(path)

          @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(law_conducted(path, code))
        end

        # A law file necessarily contains the pattern it forbids — detector,
        # fix text, bad fixture. Law.conduct neutralizes those lines (keeping
        # line numbers) before law judges law/; that only covered Law.scan,
        # so every REGISTRY law read law/ raw and NULL_BLINDNESS flagged
        # law/null_blindness.rb's own detector. One read site, so every law
        # sees the same conducted text.
        def law_conducted(path, code)
          return code unless path.to_s.match?(%r{/law/[^/]+\.rb\z})

          require law_definition_path(path) unless defined?(Law)
          Law.conduct(code)
        end

        def law_definition_path(path)
          candidate_root = Master.master_root(root: @root)
          candidate = File.join(candidate_root, "law", "definition")
          return candidate if File.file?("#{candidate}.rb")

          File.join(Master::ROOT, "law", "definition")
        end

        def read_disk(path)
          validation = validate_file(path)
          validation.err? ? validation : Result.ok(File.read(path, encoding: "UTF-8"))
        end

        def validate_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)
          return Result.err("symlink not allowed: #{path}", category: :validation) if File.symlink?(path)
          return Result.err("binary file skipped: #{path}", category: :validation) if Master.binary_file?(path)
          return Result.err("file too large: #{path}", category: :validation) if File.size(path) > MAX_FILE_BYTES

          Result.ok(path)
        rescue StandardError => e
          Result.err("file unreadable: #{e.class}: #{e.message}", category: :validation)
        end

        def parse_ruby(code, path)
          return unless Master.language_for(path) == "ruby"

          result = Prism.parse(code)
          return result.value if result.success?

          @bus&.publish("scan:syntax_fault", path:, error_count: result.errors.size)
          nil
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path:, error: e.message)
          nil
        end

        def apply_laws(code:, ast:, path:, law_set:)
          lexical, structural, semantic = partition_laws(law_set, ast)
          findings = deterministic_findings({ lexical:, structural: }, code:, ast:, path:)

          # Keep semantic violations/opportunities independent from lexical
          # findings. A fatal deterministic hit must not suppress meaning-based
          # assessment of the same file; otherwise one early result can hide the
          # other streams.
          read = semantic_findings(findings, Reading.new(path:, code:, ast:, laws: semantic))
          findings + Array(read).map { |finding| from_the_model(finding) }
        end
        # Public: the whole of what a scan concludes about a text, with no file read.
        public :apply_laws

        # A model's reading names its findings freely, often after a registered law, and two
        # readings of one file need not agree. Marked, so a repair's gates can tell it from a
        # detector's: unmarked, NO_CHANGELOG_COMMENT and WHY_NOT_WHAT on lines a repair never
        # touched refused it as new violations.
        def from_the_model(finding)
          row = finding.is_a?(Hash) ? finding : finding.to_h
          row.merge(stream: :semantic)
        end

        # One file's due model read, as semantic_findings replays, puts off, refuses or makes it.
        Reading = Data.define(:path, :code, :ast, :laws) do
          def subject(relative) = FindingCache::Subject.new(relative, code, laws, ast)
        end

        # Laws that read only this file's text replay their findings when the text is unchanged
        # (FindingCache); the rest run every time.
        def deterministic_findings(passes, code:, ast:, path:)
          pure = passes.transform_values { |laws| laws.select { |law| @finding_cache.cacheable?(law) } }
          live = passes.to_h { |pass, laws| [pass, laws - pure[pass]] }
          relative = relative_progress_path(path)

          replayed = @finding_cache.fetch(FindingCache::Subject.new(relative, code, pure.values.flatten, ast)) do
            run_passes(pure, code:, ast:, path:)
          end
          replayed + run_passes(live, code:, ast:, path:)
        end

        def run_passes(passes, code:, ast:, path:)
          passes.flat_map { |pass, laws| run_law_pass(pass:, laws:, code:, ast:, path:) }
        end

        # The slice moves by one window a day, so a tenth read per run covers the tree in ten days,
        # and two scans on the same day still ask the same questions.
        # Julian day is monotonic across New Year; yday would repeat sampling buckets at the year boundary.
        def rotation_day = Date.today.jd

        def partition_laws(law_set, ast)
          semantic = []
          structural = []
          lexical = []
          law_set.each do |law|
            if semantic_law?(law)
              semantic << law
            elsif ast && law.respond_to?(:check_ast)
              structural << law
            else
              lexical << law
            end
          end
          [lexical, structural, semantic]
        end

        def run_law_pass(pass:, laws:, code:, ast:, path:)
          @bus&.publish("scan:pass", path:, pass:, law_count: laws.size)
          laws.each_with_index.flat_map do |law, index|
            token = begin_law_progress(pass:, law:, index: index + 1, total: laws.size, path:)
            begin
              run_law(law:, code:, ast:, path:)
            rescue StandardError => e
              raise unless pass.to_sym == :semantic && semantic_inconclusive?(e)

              record_semantic_inconclusive(path:, law:, error: e)
              []
            ensure
              end_law_progress(token)
            end
          end
        end

        # `defined?` rather than a bare constant: this file is reachable from
        # `require "master"` alone, and Laws::SemanticLaw only exists once
        # review/scan/law_tree has loaded law/. Naming it unguarded
        # turned every scan on that path into "scan failed: uninitialized
        # constant", which reads as a broken file rather than a missing require.
        #
        # A law that takes a model (set_agent, as Laws::NeedsModel declares) is
        # a semantic law whatever its class: AdversarialLaw and CommentDriftLaw
        # sat in the lexical pass, so every file, clean ones included, paid a
        # model call and the clean-file sample gated nothing.
        def semantic_law?(law)
          semantic_class = defined?(Master::Review::Scan::Laws::SemanticLaw) &&
                           Master::Review::Scan::Laws::SemanticLaw
          return true if semantic_class && law.is_a?(semantic_class)
          return true if law.respond_to?(:set_agent)

          law.respond_to?(:id) && law.id.to_s == "semantic"
        end

        def annotate_findings(findings, fingerprint:)
          Array(findings).map do |finding|
            Master::Review::Scan::LawHealth.annotate(add_fingerprint(finding, fingerprint:))
          end
        end

        def add_fingerprint(finding, fingerprint:)
          meta = { fingerprint: }
          return finding.merge(meta) if finding.respond_to?(:merge)
          return finding.to_h.merge(meta) if finding.respond_to?(:to_h)

          finding
        end

        def run_law(law:, code:, ast:, path:)
          LawTiming.measure(law) do
            next law.check(code, path:) unless ast && law.respond_to?(:check_ast)

            law.check_ast(ast, code, path:)
          end
        end

        def publish_scan_result(path:, depth:, findings:)
          @bus&.publish("scan:complete", path:, depth:, count: findings.size, top_laws: top_laws(findings))
        end

        def top_laws(findings, limit: 3)
          findings.each_with_object(Hash.new(0)) do |finding, counts|
            law = finding_law(finding)
            counts[law] += 1 if law
          end.sort_by { |law, count| [-count, law] }.first(limit).to_h
        end

        def finding_law(finding)
          law =
            if finding.respond_to?(:[])
              finding[:law] || finding[:law_id] || finding["law"] || finding["law_id"]
            elsif finding.respond_to?(:law)
              finding.law
            elsif finding.respond_to?(:law_id)
              finding.law_id
            end

          law.to_s unless law.nil? || law.to_s.empty?
        end

      end
    end
  end
end
