# frozen_string_literal: true

require "rbconfig"
require "set"
require "yaml"
require_relative "../lib/io/exec"

module Operator
  # One bounded runtime adapter for the imported ratchet and lint Laws.
  # Detection stays in its focused source scanner or registered pub5 check.
  class LawInstrumentRunner
    ROOT = File.expand_path("../..", __dir__)
    CHECK_RUNNER = File.join(ROOT, "master", "checks", "runner.rb")
    REGISTRY_FILE = File.join(ROOT, "registry", "laws.yml")
    BASELINE_FILE = File.join(ROOT, "master", "data", "law_ratchets.yml")
    PROCESS_TIMEOUT = 1_800

    LINT_SPECS = {
      "LINT_ADHOC_EMPTY" => { file: "adhoc_empty_lint", constant: "AdhocEmptyLint", method: :scan, mode: :single, scope: :views },
      "LINT_ASSET_URL" => { file: "asset_url_lint", constant: "AssetUrlLint", method: :scan, mode: :grouped, scope: :views_styles },
      "LINT_BREAKPOINT" => { file: "breakpoint_lint", constant: "BreakpointLint", method: :scan, mode: :grouped, scope: :styles },
      "LINT_CHROME_I18N" => { file: "chrome_i18n_lint", constant: "ChromeI18nLint", method: :scan, mode: :grouped, scope: :views_controllers },
      "LINT_CSS_COVERAGE" => { file: "css_coverage_lint", constant: "CssCoverageLint", method: :scan, mode: :grouped, scope: :views_styles },
      "LINT_EMPTY_STATE" => { file: "empty_state_lint", constant: "EmptyStateLint", method: :scan, mode: :grouped, scope: :views },
      "LINT_LAYOUT_STABILITY" => { file: "layout_stability_lint", constant: "LayoutStabilityLint", method: :findings, mode: :grouped, scope: :views_styles },
      "LINT_DESTRUCTIVE_ACTION" => { file: "rails/operator/destructive_action_lint", constant: "DestructiveActionLint", method: :scan, mode: :grouped, scope: :views },
      "LINT_FALLBACK_DRIFT" => { file: "rails/operator/fallback_drift_lint", constant: "FallbackDriftLint", method: :run, mode: :boolean, scope: :views_styles },
      "LINT_MODEL_CONTRACT" => { file: "rails/operator/model_contract_lint", constant: "ModelContractLint", method: :scan, mode: :grouped, scope: :models },
      "LINT_RHYTHM" => { file: "rhythm_lint", constant: "RhythmLint", method: :run, mode: :boolean, scope: :styles },
      "LINT_SCALE" => { check: "scale_ratchet", scope: :styles },
      "LINT_TYPOGRAPHY" => { check: "typography_contract", scope: :styles },
      "LINT_VISUAL_CONTRACT" => { check: "visual_contract", scope: :visual },
      "LINT_WORD_BOUNDARY" => { method: :word_boundary, scope: :laws }
    }.freeze

    RATCHET_IDS = %w[
      RATCHET_MASTER_YAML RATCHET_LAW_REACH_AND_BLIND
      RATCHET_LAW_SATURATION_AND_SILENT RATCHET_AUTOFIX
      RATCHET_FIXTURE_AND_DEP RATCHET_SELF_FINDINGS RATCHET_REACH
      RATCHET_NAMESPACE RATCHET_SPRAWL RATCHET_SPINE RATCHET_NAME
      RATCHET_COMMAND RATCHET_ENTRYPOINT RATCHET_RAILS_LINT
      RATCHET_CSS_BUDGET RATCHET_FILE_LENGTH RATCHET_COVERAGE
      RATCHET_CSS_CONSTITUTION
    ].freeze

    def self.run(id) = new.run(id)

    def run(id)
      key = id.to_s
      return run_lint(key) if LINT_SPECS.key?(key)
      return run_ratchet(key) if RATCHET_IDS.include?(key)

      warn "law_instrument0: unknown instrument #{key.inspect}"
      64
    rescue StandardError => e
      warn "law_instrument0: #{key}: #{e.class}: #{e.message}"
      70
    end

    private

    def law_rows
      @law_rows ||= YAML.safe_load_file(REGISTRY_FILE, aliases: true).fetch("laws")
    end

    def baseline
      @baseline ||= YAML.safe_load_file(BASELINE_FILE, aliases: true)
    end

    def run_lint(id)
      spec = LINT_SPECS.fetch(id)
      return run_check(spec.fetch(:check)) if spec[:check]
      return run_word_boundary if spec[:method] == :word_boundary

      count = input_count(spec.fetch(:scope))
      return inconclusive(id, "no source files reached for #{spec[:scope]}") if count.zero?

      require File.join(__dir__, "#{spec.fetch(:file)}.rb")
      mod = Operator.const_get(spec.fetch(:constant), false)
      findings = Array(mod.public_send(spec.fetch(:method)))

      case spec.fetch(:mode)
      when :boolean
        findings ? pass(id, "scanner completed across #{count} scoped source files") : fail(id, "scanner reported a violation")
      when :single
        ceiling = Integer(mod.const_get(:BASELINE, false))
        findings.size > ceiling ? fail(id, "#{findings.size} findings exceed baseline #{ceiling}", findings) :
          pass(id, "#{findings.size} findings within baseline #{ceiling}")
      when :grouped
        compare_grouped(id, mod, findings)
      else
        fail(id, "unsupported instrument mode #{spec[:mode].inspect}")
      end
    end

    def compare_grouped(id, mod, findings)
      baselines = mod.const_get(:BASELINES, false)
      expected = baselines.keys.map(&:to_s)
      unknown = findings.reject { |finding| finding.respond_to?(:kind) && expected.include?(finding.kind.to_s) }
      return fail(id, "#{unknown.size} findings have no baseline kind", unknown) unless unknown.empty?

      over = []
      lower = []
      baselines.each do |kind, ceiling|
        number = findings.count { |finding| finding.kind.to_s == kind.to_s }
        over << "#{kind}=#{number} > #{ceiling}" if number > ceiling
        lower << "#{kind}=#{number} < #{ceiling}" if number < ceiling
      end
      return fail(id, over.join("; "), findings) unless over.empty?

      lower.each { |line| puts "law_instrument0: #{id}: lower count #{line}; reduce its baseline deliberately" }
      pass(id, "#{findings.size} findings within #{baselines.size} per-kind baselines")
    end

    def run_word_boundary
      bad = /\\[.?()\[\]{}|*+^$\/]\\b|\\b\\[.?()\[\]{}|*+^$\/]/
      paths = [
        File.join(ROOT, "registry", "laws.yml"),
        *Dir.glob(File.join(ROOT, "laws", "**", "*.rb")),
        *Dir.glob(File.join(ROOT, "master", "checks", "lib", "**", "*.rb")),
        *Dir.glob(File.join(ROOT, "master", "lib", "**", "*.rb"))
      ].uniq.select { |path| File.file?(path) }
      return inconclusive("LINT_WORD_BOUNDARY", "no Law or Ruby source files reached") if paths.empty?

      hits = []
      paths.each do |path|
        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
          next unless line.include?("\\b")
          next if line.lstrip.start_with?("#")
          next unless line.match?(bad)

          hits << "#{relative(path)}:#{number}: #{line.strip}"
        end
      end
      return fail("LINT_WORD_BOUNDARY", "#{hits.size} invalid \b escape(s)", hits) unless hits.empty?

      pass("LINT_WORD_BOUNDARY", "#{paths.size} Law and scanner source files scanned")
    end

    def input_count(scope)
      patterns = case scope
      when :views then ["rails/**/app/views/**/*.erb"]
      when :styles then ["rails/**/app/assets/stylesheets/**/*.{scss,css}"]
      when :views_styles then ["rails/**/app/views/**/*.erb", "rails/**/app/assets/stylesheets/**/*.{scss,css}"]
      when :views_controllers then ["rails/**/app/views/**/*.erb", "rails/**/app/controllers/**/*.rb"]
      when :models then ["rails/**/app/models/**/*.rb"]
      when :visual then ["rails/**/app/views/**/*.erb"]
      when :laws then ["laws/**/*.rb"]
      else []
      end
      patterns.sum { |pattern| Dir.glob(File.join(ROOT, pattern)).size }
    end

    def run_ratchet(id)
      case id
      when "RATCHET_MASTER_YAML" then ratchet_master_yaml
      when "RATCHET_LAW_REACH_AND_BLIND" then ratchet_law_reach_and_blind
      when "RATCHET_LAW_SATURATION_AND_SILENT" then ratchet_saturation
      when "RATCHET_AUTOFIX" then ratchet_autofix
      when "RATCHET_FIXTURE_AND_DEP" then ratchet_fixture_and_dep
      when "RATCHET_SELF_FINDINGS" then ratchet_self_findings
      when "RATCHET_REACH" then ratchet_reach
      when "RATCHET_NAMESPACE" then ratchet_namespace
      when "RATCHET_SPRAWL" then ratchet_sprawl
      when "RATCHET_SPINE" then ratchet_count(id, "spine_ruby_files") { |paths| paths.count { |path| path.match?(/\Acore\/.*\.rb\z/) } }
      when "RATCHET_NAME" then ratchet_name
      when "RATCHET_COMMAND" then ratchet_count(id, "command_ruby_files") { |paths| paths.count { |path| path.match?(/\Amaster\/commands\/[^\/]+\.rb\z/) } }
      when "RATCHET_ENTRYPOINT" then ratchet_entrypoints
      when "RATCHET_RAILS_LINT" then ratchet_rails_lint
      when "RATCHET_CSS_BUDGET" then ratchet_css_budget
      when "RATCHET_FILE_LENGTH" then run_test_file("rails/test/file_length_ratchet_test.rb")
      when "RATCHET_COVERAGE" then run_test_file("rails/test/coverage_ratchet_test.rb")
      when "RATCHET_CSS_CONSTITUTION" then run_check("css_constitution")
      else 64
      end
    end

    def ratchet_master_yaml
      ids = File.read(REGISTRY_FILE, encoding: "UTF-8").scan(/^  ([A-Z][A-Z0-9_]+):\s*$/).flatten
      errors = []
      errors << "duplicate Law IDs in registry/laws.yml" unless ids.uniq == ids
      errors << "registry has no Law rows" if law_rows.empty?
      law_rows.each do |id, row|
        errors << "#{id}: missing kind" if row["kind"].to_s.empty?
        source = row["file"].to_s
        errors << "#{id}: missing source file #{source.inspect}" if source.empty? || !File.file?(File.join(ROOT, source))
      end
      finish("RATCHET_MASTER_YAML", errors, "one canonical registry; #{law_rows.size} rows, unique IDs and present Law sources")
    end

    def imported_rows
      law_rows.select { |_id, row| %w[ratchet lint].include?(row["kind"]) }
    end

    def ratchet_law_reach_and_blind
      errors = []
      imported_rows.each do |id, row|
        metadata = row["pub4"].is_a?(Hash) ? row["pub4"] : {}
        errors << "#{id}: no named runtime instrument" unless metadata["instrument"] == "law_instruments"
        errors << "#{id}: instrument ID differs from Law ID" unless metadata["instrument_id"] == id
        proof = row["proved_by"].to_s
        errors << "#{id}: proof target missing" if proof.empty? || !File.file?(File.join(ROOT, proof))
      end
      finish("RATCHET_LAW_REACH_AND_BLIND", errors, "#{imported_rows.size} ratchet/lint Laws reach their named runner and proof target")
    end

    # The original Law makes silence observational, not a monotonic failure:
    # zero findings can mean a healthy corpus or an applicability gap.
    def ratchet_saturation
      silent = law_rows.count do |_id, row|
        source = File.join(ROOT, row["file"].to_s)
        next true unless File.file?(source)
        !File.read(source, encoding: "UTF-8").match?(/^\s*(?:detect|check|detector|adapter|ask|practice)\b/)
      end
      puts "law_instrument0: RATCHET_LAW_SATURATION_AND_SILENT: #{law_rows.size} Laws; #{silent} silent declarations (observational only)"
      0
    end

    def ratchet_autofix
      allowed = %w[never review automatic]
      errors = []
      law_rows.each do |id, row|
        mode = row["autofix"].to_s
        errors << "#{id}: unknown autofix mode #{mode.inspect}" unless allowed.include?(mode)
        next unless mode == "automatic"

        source = File.join(ROOT, row["file"].to_s)
        body = File.file?(source) ? File.read(source, encoding: "UTF-8") : ""
        errors << "#{id}: automatic fix has no transform/fix declaration" unless body.match?(/\b(?:transform|fix)\b/)
      end
      finish("RATCHET_AUTOFIX", errors, "all #{law_rows.size} autofix modes are valid and automatic claims name a transform")
    end

    def ratchet_fixture_and_dep
      errors = []
      imported_rows.each do |id, row|
        proof = row["proved_by"].to_s
        errors << "#{id}: missing proof path" if proof.empty?
        errors << "#{id}: proof file missing: #{proof}" unless proof.empty? || File.file?(File.join(ROOT, proof))
        metadata = row["pub4"].is_a?(Hash) ? row["pub4"] : {}
        errors << "#{id}: no matching instrument registration" unless metadata["instrument_id"] == id
      end
      finish("RATCHET_FIXTURE_AND_DEP", errors, "all imported ratchet/lint Laws name an extant shared proof and matching instrument")
    end

    def ratchet_self_findings
      errors = []
      imported_rows.each do |id, row|
        source = File.join(ROOT, row["file"].to_s)
        body = File.file?(source) ? File.read(source, encoding: "UTF-8") : ""
        pattern = /Law\.define\s*\(?\s*:#{Regexp.escape(id)}\b/
        errors << "#{id}: source does not declare its own Law ID" unless body.match?(pattern)
      end
      finish("RATCHET_SELF_FINDINGS", errors, "#{imported_rows.size} imported Law source files declare their own IDs")
    end

    def ratchet_reach
      registered = law_rows.values.map { |row| row["file"].to_s }.to_set
      candidates = Dir.glob(File.join(ROOT, "laws", "pub4", "*.rb")).map { |path| relative(path) }
      orphans = candidates.reject { |path| registered.include?(path) }
      finish("RATCHET_REACH", orphans.map { |path| "unregistered imported Law source #{path}" }, "#{candidates.size} imported Law files indexed")
    end

    def ratchet_namespace
      paths = [
        *Dir.glob(File.join(ROOT, "core", "**", "*.rb")),
        *Dir.glob(File.join(ROOT, "master", "lib", "**", "*.rb")),
        *Dir.glob(File.join(ROOT, "master", "checks", "lib", "**", "*.rb"))
      ].uniq
      missing = paths.reject { |path| File.read(path, encoding: "UTF-8").match?(/^\s*(?:module|class)\s+[A-Z]/) }
      finish("RATCHET_NAMESPACE", missing.map { |path| "#{relative(path)} has no module/class namespace" }, "#{paths.size} core and check implementation files inspected")
    end

    def ratchet_sprawl
      paths = tracked_paths
      counts = baseline.fetch("source_counts")
      errors = []
      counts.each do |root, ceiling|
        count = paths.count { |path| path.start_with?("#{root}/") && source_path?(path) }
        errors << "#{root}: #{count} source files exceeds #{ceiling}" if count > Integer(ceiling)
        puts "law_instrument0: RATCHET_SPRAWL: #{root} #{count}/#{ceiling}" if count < Integer(ceiling)
      end
      finish("RATCHET_SPRAWL", errors, "tracked source populations within pub5 snapshot ceilings")
    end

    def ratchet_count(id, key)
      current = yield(tracked_paths)
      ceiling = Integer(baseline.fetch(key))
      errors = current > ceiling ? ["#{current} exceeds #{ceiling}"] : []
      puts "law_instrument0: #{id}: new low #{current}/#{ceiling}" if current < ceiling
      finish(id, errors, "#{current}/#{ceiling}")
    end

    def ratchet_name
      names = tracked_paths.select do |path|
        path.end_with?(".rb") && File.basename(path).match?(/\A(?:util|utils|helper|helpers|common|misc|base|stuff)\.rb\z/i)
      end
      ceiling = Integer(baseline.fetch("vague_ruby_names"))
      errors = names.size > ceiling ? names : []
      finish("RATCHET_NAME", errors, "#{names.size}/#{ceiling} vague Ruby basenames")
    end

    def ratchet_entrypoints
      count = git("ls-files", "--stage").lines.count { |line| line.start_with?("100755 ") }
      ceiling = Integer(baseline.fetch("executable_files"))
      errors = count > ceiling ? ["#{count} executable files exceeds #{ceiling}"] : []
      puts "law_instrument0: RATCHET_ENTRYPOINT: lower count #{count}/#{ceiling}" if count < ceiling
      finish("RATCHET_ENTRYPOINT", errors, "#{count}/#{ceiling} tracked executable files")
    end

    def ratchet_rails_lint
      missing = LINT_SPECS.filter_map do |id, spec|
        next if spec[:check] || spec[:method] == :word_boundary
        path = File.join(__dir__, "#{spec[:file]}.rb")
        "#{id}: #{relative(path)} missing" unless File.file?(path)
      end
      finish("RATCHET_RAILS_LINT", missing, "#{LINT_SPECS.size}/15 lint Laws have a registered source or check")
    end

    def ratchet_css_budget
      count = tracked_paths.count { |path| path.start_with?("rails/") && path.match?(/\.(?:css|scss)\z/) }
      ceiling = Integer(baseline.fetch("rails_stylesheets"))
      return fail("RATCHET_CSS_BUDGET", "#{count} stylesheet files exceeds #{ceiling}") if count > ceiling

      result = run_check("design_metrics")
      return result unless result.zero?
      pass("RATCHET_CSS_BUDGET", "#{count}/#{ceiling} source stylesheets; design_metrics passed")
    end

    def ratchet_coverage
      candidates = [
        File.join(ROOT, "coverage", ".resultset.json"),
        *Dir.glob(File.join(ROOT, "rails", "*", "coverage", ".resultset.json"))
      ]
      return inconclusive("RATCHET_COVERAGE", "no SimpleCov resultset exists; source-only counts cannot claim coverage") if candidates.empty?

      parsed = candidates.filter_map do |path|
        JSON.parse(File.read(path))
        relative(path)
      rescue JSON::ParserError
        nil
      end
      return fail("RATCHET_COVERAGE", "coverage resultsets exist but none parse") if parsed.empty?
      inconclusive("RATCHET_COVERAGE", "resultsets #{parsed.join(', ')} exist, but pub5 has no ratified per-app coverage floor table")
    end

    def run_test_file(path)
      absolute = File.join(ROOT, path)
      return fail(path, "ratchet test file is missing") unless File.file?(absolute)

      output, process = Master::Io::Exec.capture2e(
        RbConfig.ruby, absolute, chdir: ROOT,
        timeout: PROCESS_TIMEOUT, raise_on_timeout: true
      )
      code = process.exitstatus || 70
      puts output.to_s unless output.to_s.empty?
      code
    rescue Master::Io::Exec::TimeoutError => e
      warn "law_instrument0: #{path} timed out: #{e.message}"
      70
    end

    def run_check(name)
      output, process = Master::Io::Exec.capture2e(
        { "CHECK_STRICT_SOFT" => "1" }, RbConfig.ruby, CHECK_RUNNER, name,
        chdir: ROOT, timeout: PROCESS_TIMEOUT, raise_on_timeout: true
      )
      code = process.exitstatus || 70
      puts output.to_s unless output.to_s.empty?
      code
    rescue Master::Io::Exec::TimeoutError => e
      warn "law_instrument0: #{name} timed out: #{e.message}"
      70
    end

    def source_path?(path)
      return false unless path.match?(/\.(?:rb|rake|erb|scss|css|js|mjs|yml|yaml|md|sh|ksh|exp|html|json)\z/i)
      return false if path.match?(%r{(?:\A|/)(?:test|spec|vendor|node_modules|tmp|build|coverage|storage|public/assets)(?:/|\z)})
      true
    end

    def tracked_paths
      @tracked_paths ||= git("ls-files", "-z").split("\0").reject(&:empty?)
    end

    def git(*args)
      output, status = Master::Io::Exec.capture2e("git", *args, chdir: ROOT, timeout: 120)
      raise "git #{args.join(' ')} failed: #{output}" unless status.success?
      output.to_s
    end

    def relative(path) = path.to_s.delete_prefix("#{ROOT}/")

    def finish(id, errors, detail)
      Array(errors).each { |message| warn "law_instrument0: #{id}: #{message}" }
      return fail(id, "#{errors.size} finding(s)", errors) unless errors.empty?
      pass(id, detail)
    end

    def pass(id, detail)
      puts "law_instrument0: #{id}: PASS: #{detail}"
      0
    end

    def fail(id, detail, evidence = [])
      Array(evidence).first(30).each { |item| warn "law_instrument0: #{id}: #{format_evidence(item)}" }
      warn "law_instrument0: #{id}: FAIL: #{detail}"
      1
    end

    def inconclusive(id, detail)
      warn "law_instrument0: #{id}: INCONCLUSIVE: #{detail}"
      3
    end

    def format_evidence(item)
      return item if item.is_a?(String)
      file = item.respond_to?(:file) ? item.file : nil
      line = item.respond_to?(:line) ? item.line : nil
      message = item.respond_to?(:message) ? item.message : item.to_s
      "#{file}#{line ? ":#{line}" : ""}: #{message}"
    end
  end
end
