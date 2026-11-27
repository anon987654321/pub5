# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "set"
require "time"
require "yaml"
require_relative "../io/process_spawn"

module Master
  module Fix
    # Read-only, target-scoped sensors for surfaces that a source scanner alone
    # cannot prove. These receipts supplement Law findings; they never turn a
    # missing adapter into a clean result, and they never deploy or mutate source.
    # This file holds the orchestration, the capture report and the shared
    # receipt support; the per-surface builders, the inventory, the runtime
    # probes and the command runner live in the surface_evidence/ parts that
    # re-open this class.
    class SurfaceEvidence
      public

      # Receipt builders for the filesystem-derived surfaces: the bounded
      # inventory census, path and file-name receipts, the literal relative
      # dependency graph, media signatures and the generated asset contract.
      private

      def tree_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        receipt("assessed_clean", evidence: {
          "method" => "bounded no-follow filesystem inventory plus FixPlan source digests",
          "target" => @target_label,
          "inventory_sha256" => inventory["digest"],
          "source_sha256" => source["digest"],
          "excluded_directory_count" => inventory["ignored_directories"].size,
          "symlink_count" => inventory["symlinks"],
        }, counts: {
          "files" => inventory["files"],
          "directories" => inventory["directories"],
          "symlinks" => inventory["symlinks"],
        })
      end

      def directory_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        receipt("assessed_clean", evidence: {
          "method" => "parent-directory census over the same no-follow inventory",
          "inventory_sha256" => inventory["digest"],
          "source_sha256" => source["digest"],
        }, counts: { "directories" => inventory["directories"] })
      end

      def file_name_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        names = inventory["records"].filter_map { |row| row[0] if row[1] == "file" }.map { |path| File.basename(path) }.sort
        receipt("assessed_clean", evidence: {
          "method" => "complete eligible and non-binary file-name inventory",
          "names_sha256" => digest_json(names),
          "source_sha256" => source["digest"],
        }, counts: { "file_names" => names.size })
      end

      def path_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        paths = inventory["records"].map(&:first).sort
        receipt("assessed_clean", evidence: {
          "method" => "relative path inventory; symlinks are recorded but never followed",
          "paths_sha256" => digest_json(paths),
          "source_sha256" => source["digest"],
        }, counts: { "paths" => paths.size })
      end

      def cross_file_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        edges = []
        unresolved = []
        unreadable = []
        text_paths = cross_file_text_paths
        text_paths.each { |path| collect_cross_file_edges(path, edges, unresolved, unreadable) }

        return cross_file_unreadable_receipt(unreadable) if unreadable.any?
        return cross_file_unresolved_receipt(unresolved, source) if unresolved.any?

        receipt("assessed_clean", evidence: {
          "method" => "resolved literal relative dependency graph",
          "edge_sha256" => digest_json(edges.sort),
          "source_sha256" => source["digest"],
        }, counts: { "source_files" => text_paths.size, "resolved_edges" => edges.size })
      end

      def cross_file_text_paths
        @plan.sources.filter_map do |item|
          path = File.expand_path(item.path, @root)
          path if File.file?(path) && !File.symlink?(path) && File.extname(path).downcase.match?(
            /\A\.(?:rb|rake|gemspec|js|mjs|cjs|ts|tsx|jsx|css|scss|sass|html|erb)\z/,
          )
        end.sort
      end

      def collect_cross_file_edges(path, edges, unresolved, unreadable)
        body = read_stable(path)
        unless body
          unreadable << relative(path)
          return
        end

        collect_ruby_edges(path, body, edges, unresolved)
        collect_module_edges(path, body, edges, unresolved)
      end

      def collect_ruby_edges(path, body, edges, unresolved)
        extension = File.extname(path).downcase
        return unless extension == ".rb" || extension == ".rake" || extension == ".gemspec"

        body.to_enum(:scan, %r{require_relative\s*[\(\s]*["']([^"']+)["']}).each do
          reference = Regexp.last_match(1)
          destination = ruby_reference_candidates(path, reference).find do |candidate|
            File.file?(candidate) && !File.symlink?(candidate)
          end
          if destination
            edges << [relative(path), relative(destination), "require_relative"]
          else
            unresolved << { "source" => relative(path), "reference" => reference, "kind" => "require_relative" }
          end
        end
      end

      def collect_module_edges(path, body, edges, unresolved)
        extension = File.extname(path).downcase
        return unless %w[.js .mjs .cjs .ts .tsx .jsx].include?(extension)

        body.to_enum(:scan, %r{(?:from\s*|import\s*\()\s*["'](\.{1,2}/[^"']+)["']}).each do
          reference = Regexp.last_match(1)
          destination = module_reference_candidates(path, reference).find do |candidate|
            File.file?(candidate) && !File.symlink?(candidate)
          end
          if destination
            edges << [relative(path), relative(destination), "module_import"]
          else
            unresolved << { "source" => relative(path), "reference" => reference, "kind" => "module_import" }
          end
        end
      end

      def cross_file_unreadable_receipt(unreadable)
        receipt("inconclusive", reason: "cross-file source reads failed for #{unreadable.first(4).join(', ')}")
      end

      def cross_file_unresolved_receipt(unresolved, source)
        receipt("violation_found",
          reason: "unresolved local references: #{unresolved.first(4).map { |row| "#{row["source"]} -> #{row["reference"]}" }.join(", ")}",
          findings: unresolved.first(40),
          evidence: { "method" => "resolved literal relative dependencies", "source_sha256" => source["digest"] })
      end

      def media_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        asset_records = recognized_asset_records(inventory)
        return media_empty_receipt(inventory) if asset_records.empty?

        measured, failures, unmeasured = measure_media_assets(asset_records)
        return media_failure_receipt(failures, inventory) if failures.any?
        return media_unmeasured_receipt(unmeasured, inventory) if unmeasured.any?

        receipt("assessed_clean", evidence: {
          "method" => "signature-checked asset inventory; no image content or accessibility inference",
          "asset_manifest_sha256" => digest_json(measured.sort),
          "inventory_sha256" => inventory["digest"],
        }, counts: { "assets" => measured.size })
      end

      def media_empty_receipt(inventory)
        receipt("not_applicable", reason: "target inventory contains no recognized media or font assets",
          evidence: { "method" => "complete target inventory", "inventory_sha256" => inventory["digest"] })
      end

      def measure_media_assets(asset_records)
        assets = asset_records.select { |_path, type, _size| type == "file" }
        unmeasured = asset_records.select { |_path, type, _size| type == "symlink" }.map do |path, _type, _size|
          "#{path} (symlink target not verified)"
        end
        failures = []
        measured = []
        assets.each { |relative_path, _type, expected_bytes| measure_media_asset(relative_path, expected_bytes, measured, failures, unmeasured) }
        [measured, failures, unmeasured]
      end

      def measure_media_asset(relative_path, expected_bytes, measured, failures, unmeasured)
        path = File.expand_path(relative_path, @root)
        return if File.symlink?(path) || !File.file?(path)

        stat = File.stat(path)
        if stat.size <= 0 || stat.size != expected_bytes
          failures << { "path" => relative_path, "reason" => "empty or unstable asset size" }
          return
        end
        header = File.open(path, "rb") { |file| file.read(4096).to_s }
        kind = asset_kind(File.extname(path).downcase, header)
        if kind == :valid
          measured << [relative_path, Digest::SHA256.file(path).hexdigest, stat.size]
        elsif kind == :invalid
          failures << { "path" => relative_path, "reason" => "asset signature does not match extension" }
        else
          unmeasured << relative_path
        end
      rescue StandardError => e
        unmeasured << "#{relative_path} (#{e.class})"
      end

      def media_failure_receipt(failures, inventory)
        receipt("violation_found", reason: "invalid media assets: #{failures.first(4).map { |row| row["path"] }.join(", ")}",
          findings: failures.first(40), evidence: { "method" => "file signature and byte stability", "inventory_sha256" => inventory["digest"] })
      end

      def media_unmeasured_receipt(unmeasured, inventory)
        receipt("inconclusive", reason: "asset type or read could not be verified: #{unmeasured.first(4).join(", ")}",
          evidence: { "method" => "file signature and byte stability", "inventory_sha256" => inventory["digest"] })
      end

      def recognized_asset_records(inventory)
        Array(inventory["records"]).select do |path, type, _size|
          %w[file symlink].include?(type) && MEDIA_EXTENSIONS.include?(File.extname(path.to_s).downcase)
        end
      end

      def asset_kind(extension, header)
        kind = fixed_header_asset_kind(extension, header)
        return kind if kind

        structured_header_asset_kind(extension, header) || :unknown
      end

      def fixed_header_asset_kind(extension, header)
        case extension
        when ".png" then header.start_with?("\x89PNG\r\n\x1a\n".b) ? :valid : :invalid
        when ".jpg", ".jpeg" then header.start_with?("\xFF\xD8\xFF".b) ? :valid : :invalid
        when ".gif" then header.start_with?("GIF87a", "GIF89a") ? :valid : :invalid
        when ".ico" then header.start_with?("\x00\x00\x01\x00".b) ? :valid : :invalid
        when ".bmp" then header.start_with?("BM") ? :valid : :invalid
        when ".tif", ".tiff" then header.start_with?("II*\x00".b, "MM\x00*".b) ? :valid : :invalid
        when ".pdf" then header.start_with?("%PDF-") ? :valid : :invalid
        when ".flac" then header.start_with?("fLaC") ? :valid : :invalid
        when ".ogg" then header.start_with?("OggS") ? :valid : :invalid
        when ".woff" then header.start_with?("wOFF") ? :valid : :invalid
        when ".woff2" then header.start_with?("wOF2") ? :valid : :invalid
        when ".ttf" then header.start_with?("\x00\x01\x00\x00".b, "true") ? :valid : :invalid
        when ".otf" then header.start_with?("OTTO") ? :valid : :invalid
        when ".webm" then header.start_with?("\x1A\x45\xDF\xA3".b) ? :valid : :invalid
        end
      end

      def structured_header_asset_kind(extension, header)
        case extension
        when ".webp" then header.bytesize >= 12 && header.start_with?("RIFF") && header.byteslice(8, 4) == "WEBP" ? :valid : :invalid
        when ".avif", ".mp4", ".mov", ".m4a" then header.bytesize >= 12 && header.byteslice(4, 4) == "ftyp" ? :valid : :invalid
        when ".svg"
          normalized = header.delete_prefix("\uFEFF").lstrip
          normalized.match?(%r{(?:\A<svg\b)|(?:\A<\?xml\b.*?<svg\b)}mi) ? :valid : :invalid
        when ".wav" then header.bytesize >= 12 && header.start_with?("RIFF") && header.byteslice(8, 4) == "WAVE" ? :valid : :invalid
        when ".mp3" then header.start_with?("ID3") || header.getbyte(0) == 0xFF && (header.getbyte(1).to_i & 0xE0) == 0xE0 ? :valid : :invalid
        when ".aac" then header.start_with?("ID3") || header.getbyte(0) == 0xFF && (header.getbyte(1).to_i & 0xF6) == 0xF0 ? :valid : :invalid
        end
      end

      def compiled_asset_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target is outside the Rails asset build surface") unless rails_target?

        begin
          compiled_asset_check_receipt
        rescue StandardError => e
          receipt("inconclusive", reason: "generated asset checker unavailable: #{error_text(e)}")
        end
      end

      def compiled_asset_check_receipt
        require_relative "../../checks/lib/source/generated_asset" unless defined?(::Deploy::GeneratedAssetCheck)
        result = ::Deploy::GeneratedAssetCheck.run
        outcome = result.respond_to?(:outcome) ? result.outcome : nil
        details = compiled_asset_details(result, outcome)
        if outcome == :passed && result.respond_to?(:conclusive?) && result.conclusive?
          receipt("assessed_clean", evidence: details, counts: { "checks" => result.checks_ran.to_i })
        elsif outcome == :failed
          receipt("violation_found", reason: "generated asset contract failed", evidence: details,
            findings: Array(result.failures).first(30))
        else
          receipt("inconclusive", reason: "generated asset check was not conclusive", evidence: details)
        end
      end

      def compiled_asset_details(result, outcome)
        {
          "checker" => "Deploy::GeneratedAssetCheck",
          "outcome" => outcome.to_s,
          "checked" => result.respond_to?(:checks_ran) ? result.checks_ran.to_i : nil,
          "inconclusive" => result.respond_to?(:unchecked) ? Array(result.unchecked).first(8) : [],
          "failures" => result.respond_to?(:failures) ? Array(result.failures).first(12) : [],
        }.compact
      end

      def ruby_reference_candidates(path, reference)
        base = File.expand_path(reference, File.dirname(path))
        [base, "#{base}.rb", File.join(base, "index.rb")].uniq
      end

      def module_reference_candidates(path, reference)
        base = File.expand_path(reference, File.dirname(path))
        [base, *%w[.js .mjs .cjs .ts .tsx .jsx].map { |extension| "#{base}#{extension}" },
         *%w[index.js index.mjs index.ts index.tsx].map { |name| File.join(base, name) }].uniq
      end

      public

      # Receipt builders for the browser-observed surfaces: rendered UI
      # coverage from a VisualPass result and the safe interactive journey
      # probes, plus the capture-row validation they share.
      private

      def target_has_frontend?
        @plan.sources.any? do |source|
          path = source.path
          path.match?(%r{(?:\A|/)(?:app/views|views|templates|frontend|src|public)/}) &&
            %w[.erb .html .htm .css .scss .js .mjs .ts .tsx .jsx].include?(File.extname(path).downcase)
        end || rails_target? && @plan.sources.any? { |source| %w[.erb .html .htm .css .scss].include?(File.extname(source.path).downcase) }
      end

      def rendered_ui_receipt
        return receipt("not_applicable", reason: "target inventory has no declared front-end surface") unless target_has_frontend?
        return receipt("inconclusive", reason: "rendered browser evidence was not produced for this pass") unless @visual_result

        if @visual_result.respond_to?(:err?) && @visual_result.err?
          return receipt("inconclusive", reason: @visual_result.message.to_s[0, 220],
            evidence: { "method" => "VisualPass", "result" => "error" })
        end

        value = result_value(@visual_result)
        return receipt("inconclusive", reason: "VisualPass returned no result payload") unless value.is_a?(Hash)
        rendered_ui_payload_receipt(value)
      rescue StandardError => e
        receipt("inconclusive", reason: "rendered UI receipt failed: #{error_text(e)}")
      end

      def rendered_ui_payload_receipt(value)
        coverage = value[:coverage] || value["coverage"] || {}
        captures = Array(value[:surface_evidence] || value["surface_evidence"])
        expected = Array(coverage[:expected] || coverage["expected"])
        actual = Array(coverage[:captured] || coverage["captured"])
        missing = Array(coverage[:missing] || coverage["missing"])
        unless expected.any? && missing.empty? && (expected - actual).empty? && captures.size >= expected.size
          return rendered_ui_incomplete_receipt(expected, actual, missing, captures)
        end
        broken = captures.reject { |row| valid_rendered_capture?(row) }
        return rendered_ui_broken_receipt(broken) if broken.any?

        rendered_ui_clean_receipt(captures, expected, actual, missing)
      end

      def rendered_ui_incomplete_receipt(expected, actual, missing, captures)
        receipt("inconclusive", reason: "rendered surface coverage incomplete",
          evidence: { "expected" => expected, "captured" => actual, "missing" => missing, "capture_records" => captures.size })
      end

      def rendered_ui_broken_receipt(broken)
        receipt("inconclusive", reason: "rendered surface lacked a stable screenshot or geometry receipt",
          evidence: { "broken" => broken.first(8) })
      end

      def rendered_ui_clean_receipt(captures, expected, actual, missing)
        receipt("assessed_clean", evidence: {
          "method" => "VisualPass CDP rendered capture plus geometry and viewport coverage",
          "coverage" => { "expected" => expected, "captured" => actual, "missing" => missing },
          "surfaces" => captures.map { |row| compact_visual_row(row) },
        }, counts: { "surfaces" => captures.size })
      end

      def interactive_receipt
        return receipt("not_applicable", reason: "target inventory has no declared front-end surface") unless target_has_frontend?
        return receipt("inconclusive", reason: "interactive behavior was not measured without a rendered browser result") unless @visual_result
        return receipt("inconclusive", reason: @visual_result.message.to_s[0, 220]) if @visual_result.respond_to?(:err?) && @visual_result.err?

        value = result_value(@visual_result)
        captures = Array(value && (value[:surface_evidence] || value["surface_evidence"]))
        return receipt("inconclusive", reason: "rendered browser result contains no interaction receipts") if captures.empty?

        unresolved = []
        violations = []
        action_count = 0
        captures.each { |row| action_count += collect_interaction_outcomes(row, unresolved, violations) }
        interactive_summary_receipt(captures, unresolved, violations, action_count)
      rescue StandardError => e
        receipt("inconclusive", reason: "interactive behavior receipt failed: #{error_text(e)}")
      end

      def collect_interaction_outcomes(row, unresolved, violations)
        journey = row_value(row, "journey")
        return 0 unless journey.is_a?(Hash)

        actions = Array(row_value(journey, "actions"))
        collect_journey_outcomes(row, journey, actions, unresolved, violations)
        actions.size
      end

      def collect_journey_outcomes(row, journey, actions, unresolved, violations)
        case row_value(journey, "status").to_s
        when "not_applicable" then nil
        when "assessed_clean" then collect_clean_journey_outcomes(row, actions, unresolved, violations)
        when "violation_found" then collect_failed_journey_outcomes(row, journey, unresolved, violations)
        else
          unresolved << { "surface" => row_value(row, "id"), "reason" => row_value(journey, "reason") || "interaction probe inconclusive" }
        end
      end

      def collect_clean_journey_outcomes(row, actions, unresolved, violations)
        failures = actions.select { |action| row_value(action, "status").to_s == "violation_found" }
        unknown = actions.reject { |action| %w[assessed_clean violation_found].include?(row_value(action, "status").to_s) }
        violations.concat(failures.map { |action| { "surface" => row_value(row, "id"), "action" => action } })
        unresolved << { "surface" => row_value(row, "id"), "actions" => unknown.first(5) } if unknown.any?
      end

      def collect_failed_journey_outcomes(row, journey, unresolved, violations)
        violations.concat(Array(row_value(journey, "failures")).map { |action| { "surface" => row_value(row, "id"), "action" => action } })
        unresolved << { "surface" => row_value(row, "id"), "reason" => "journey detected a behavioral failure" } if Array(row_value(journey, "failures")).empty?
      end

      def interactive_summary_receipt(captures, unresolved, violations, action_count)
        return interactive_violation_receipt(violations) if violations.any?
        return interactive_unresolved_receipt(unresolved) if unresolved.any?
        return interactive_no_actions_receipt(captures) if action_count.zero?

        receipt("assessed_clean", evidence: {
          "method" => "safe same-origin browser journey probes; destructive and non-GET form actions are excluded",
          "surfaces" => captures.map { |row| row_value(row, "id") },
          "action_count" => action_count,
          "journey_sha256" => digest_json(captures.map { |row| compact_visual_row(row) }),
        }, counts: { "surfaces" => captures.size, "actions" => action_count })
      end

      def interactive_violation_receipt(violations)
        receipt("violation_found", reason: "one or more safe interaction journeys failed",
          evidence: { "violations" => violations.first(10) }, findings: violations.first(30))
      end

      def interactive_unresolved_receipt(unresolved)
        receipt("inconclusive", reason: "interaction evidence missing or incomplete for one or more captured surfaces",
          evidence: { "unresolved" => unresolved.first(10) })
      end

      def interactive_no_actions_receipt(captures)
        receipt("not_applicable", reason: "rendered surfaces exposed no safe, measurable interactive controls",
          evidence: { "surfaces" => captures.map { |row| row_value(row, "id") }, "actions" => 0 })
      end

      def valid_rendered_capture?(row)
        return false unless row_status(row, "rendered_status") == "assessed_clean"
        return false unless row_value(row, "screenshot_sha256").to_s.match?(/\A[a-f0-9]{64}\z/)
        return false unless row_value(row, "geometry_sha256").to_s.match?(/\A[a-f0-9]{64}\z/)

        count = Integer(row_value(row, "element_count"))
        count >= 0
      rescue ArgumentError, TypeError
        false
      end

      def compact_visual_row(row)
        journey = row_value(row, "journey")
        {
          "id" => row_value(row, "id"),
          "app" => row_value(row, "app"),
          "viewport" => row_value(row, "viewport"),
          "rendered_status" => row_value(row, "rendered_status"),
          "screenshot_sha256" => row_value(row, "screenshot_sha256"),
          "geometry_sha256" => row_value(row, "geometry_sha256"),
          "element_count" => row_value(row, "element_count"),
          "journey_status" => row_value(journey, "status"),
          "journey_actions" => Array(row_value(journey, "actions")).map do |action|
            action.select { |key, _| %w[kind selector label status changed from to].include?(key.to_s) }
          end,
        }.compact
      end

      public

      # Receipt builders for the surfaces that exercise other processes or
      # manifests: target-scoped test runners and the local deployment
      # contract, plus the eligibility checks and manifest helpers they share.
      private

      def target_has_tests?(inventory)
        if @target_label == "RAILS/__shared" || @target_label.start_with?("RAILS/__shared/")
          return %w[amber brgen bsdports].any? do |name|
            File.directory?(File.join(@root, "RAILS", name, "test"))
          end
        end

        inventory["records"].any? do |path, type, _size|
          type == "file" && (
            path.match?(%r{(?:\A|/)(?:test|tests|spec)(?:/|\z)}) ||
              File.basename(path).match?(/(?:_test|_spec)\.(?:rb|js|ts|jsx|tsx|mjs)\z/)
          )
        end
      end

      def target_has_deployment?
        rails_target? || @target_label == "OPENBSD" || @target_label.start_with?("OPENBSD/") ||
          @plan.sources.any? do |source|
            File.basename(source.path).match?(/\A(?:Procfile|Dockerfile|compose\.ya?ml|.*deploy.*|.*\.service)\z/i) ||
              source.path.match?(%r{(?:deploy|deployment|helm|terraform|k8s)/})
          end
      end

      def deployment_surface?
        target_has_deployment?
      end

      def test_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target contains no test or spec files") unless target_has_tests?(inventory)
        return test_deferred_receipt(source) unless @run_expensive

        commands = test_commands(inventory)
        return receipt("inconclusive", reason: "test files exist but no safe target-specific runner was discovered") if commands.empty?

        outcomes = run_test_commands(commands)
        failed = outcomes.select { |row| row["status"] == "failed" }
        inconclusive = outcomes.select { |row| row["status"] == "inconclusive" }
        evidence = test_evidence(source, outcomes)
        return test_failed_receipt(evidence, failed) if failed.any?
        return test_inconclusive_receipt(evidence, inconclusive) if inconclusive.any?

        receipt("assessed_clean", evidence:, counts: { "commands" => outcomes.size })
      rescue StandardError => e
        receipt("inconclusive", reason: "test runner unavailable: #{error_text(e)}")
      end

      def test_deferred_receipt(source)
        receipt("inconclusive", reason: "test execution deferred until a clean scanner candidate pass",
          evidence: { "source_sha256" => source["digest"] })
      end

      def run_test_commands(commands)
        deadline = command_deadline(TEST_TIMEOUT)
        commands.map do |definition|
          command = execute_command(
            definition.fetch(:argv),
            chdir: definition.fetch(:chdir),
            env: definition.fetch(:env, {}),
            deadline:,
          )
          command.merge("label" => definition.fetch(:label))
        end
      end

      def test_evidence(source, outcomes)
        {
          "method" => "target-specific test runner; no shell command interpolation",
          "source_sha256" => source["digest"],
          "commands" => outcomes.map { |row| row.slice("label", "status", "exit_status", "timed_out", "duration_ms", "stdout_sha256", "stderr_sha256", "message") },
        }
      end

      def test_failed_receipt(evidence, failed)
        receipt("violation_found", reason: "one or more test runners failed", evidence:, findings: failed.first(20))
      end

      def test_inconclusive_receipt(evidence, inconclusive)
        receipt("inconclusive", reason: "one or more test runners timed out or were unavailable", evidence:, findings: inconclusive.first(20))
      end

      def deployment_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target has no local deployment contract") unless deployment_surface?

        manifests = []
        problems = []
        collect_rails_apps_contract(manifests, problems)
        collect_openbsd_inventory_contract(manifests, problems)
        collect_master_web_contract(manifests, problems)
        deployment_summary_receipt(problems, manifests, source)
      rescue StandardError => e
        receipt("inconclusive", reason: "deployment contract probe failed: #{error_text(e)}")
      end

      def collect_rails_apps_contract(manifests, problems)
        return unless @tree == "RAILS" || @target_label.start_with?("OPENBSD")

        apps_path = File.join(@root, "RAILS", "apps.yml")
        unless File.file?(apps_path) && !File.symlink?(apps_path)
          problems << "RAILS/apps.yml is missing or symlinked"
          return
        end

        begin
          validate_rails_deploy_apps(YAML.safe_load_file(apps_path).fetch("apps"), manifests, problems)
        rescue StandardError => e
          problems << "RAILS/apps.yml: #{error_text(e)}"
        end
      end

      def validate_rails_deploy_apps(apps, manifests, problems)
        selected_apps(apps.keys).each do |name|
          metadata = apps.fetch(name)
          script = metadata["deploy_script"].to_s
          deploy_root = metadata["deploy_root"].to_s
          validate_repo_path(script, "deploy script", problems)
          validate_repo_path(deploy_root, "deploy root", problems)
          script_path = File.expand_path(script, @root)
          root_path = File.expand_path(deploy_root, @root)
          validate_deploy_app_paths(name, script_path, root_path, problems)
          manifests << { "app" => name, "deploy_script" => script, "deploy_root" => deploy_root }
        end
      end

      def validate_deploy_app_paths(name, script_path, root_path, problems)
        problems << "#{name}: deploy script is missing or not a regular file" unless File.file?(script_path) && !File.symlink?(script_path)
        problems << "#{name}: deploy root is missing or not a directory" unless File.directory?(root_path) && !File.symlink?(root_path)
        problems << "#{name}: deploy script is not executable" if File.file?(script_path) && !File.executable?(script_path)
      end

      def collect_openbsd_inventory_contract(manifests, problems)
        return unless @target_label == "OPENBSD" || @target_label.start_with?("OPENBSD/")

        collect_openbsd_inventory_manifest(manifests, problems)
        vps_script = File.join(@root, "OPENBSD", "mirror", "bin", "vps-deploy")
        problems << "OPENBSD/bin/vps-deploy is missing or not executable" unless File.file?(vps_script) && !File.symlink?(vps_script) && File.executable?(vps_script)
      end

      def collect_openbsd_inventory_manifest(manifests, problems)
        inventory_path = File.join(@root, "OPENBSD", "deploy_inventory.json")
        unless File.file?(inventory_path) && !File.symlink?(inventory_path)
          problems << "OPENBSD/deploy_inventory.json is missing or symlinked"
          return
        end

        begin
          openbsd_inventory_findings(inventory_path, manifests, problems)
        rescue StandardError => e
          problems << "OPENBSD/deploy_inventory.json: #{error_text(e)}"
        end
      end

      def openbsd_inventory_findings(inventory_path, manifests, problems)
        data = JSON.parse(File.read(inventory_path, encoding: "UTF-8"))
        apps = Array(data["apps"])
        rails_apps = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).fetch("apps")
        inventory_by_name = apps.to_h { |row| [row.fetch("name"), row] }
        openbsd_inventory_schema_findings(data, apps, rails_apps, problems)
        validate_openbsd_inventory_apps(inventory_by_name, rails_apps, problems)
        manifests << { "inventory" => "OPENBSD/deploy_inventory.json", "apps" => apps.size }
      end

      def openbsd_inventory_schema_findings(data, apps, rails_apps, problems)
        return unless @target_label == "OPENBSD"

        inventory_names = apps.map { |row| row["name"].to_s }.sort
        problems << "OPENBSD deployment inventory names differ from RAILS/apps.yml" unless inventory_names == rails_apps.keys.map(&:to_s).sort
        problems << "OPENBSD deploy inventory schema is unsupported" unless data["schema"].to_i == 1
        problems << "OPENBSD deploy inventory generated_from is not RAILS/apps.yml" unless data["generated_from"].to_s == "RAILS/apps.yml"
      end

      def validate_openbsd_inventory_apps(inventory_by_name, rails_apps, problems)
        selected_apps(rails_apps.keys).each do |name|
          row = inventory_by_name[name]
          problems << "OPENBSD deploy inventory is missing #{name}" unless row
          next unless row

          metadata = rails_apps.fetch(name)
          %w[domain port].each do |key|
            problems << "#{name}: deploy inventory #{key} differs from RAILS/apps.yml" unless row[key].to_s == metadata[key].to_s
          end
        end
      end

      def collect_master_web_contract(manifests, problems)
        return unless @target_label == "MASTER/web" || @target_label.start_with?("MASTER/web/")

        master_web_inventory_findings(manifests, problems)
        vps_script = File.join(@root, "OPENBSD", "mirror", "bin", "vps-deploy")
        problems << "OPENBSD/bin/vps-deploy is missing or not executable" unless File.file?(vps_script) && !File.symlink?(vps_script) && File.executable?(vps_script)
      end

      def master_web_inventory_findings(manifests, problems)
        inventory_path = File.join(@root, "OPENBSD", "deploy_inventory.json")
        unless File.file?(inventory_path) && !File.symlink?(inventory_path)
          problems << "OPENBSD/deploy_inventory.json is missing or symlinked"
          return
        end

        begin
          found, manifest = master_inventory_findings(inventory_path)
          problems.concat(found)
          manifests << manifest if manifest
        rescue StandardError => e
          problems << "OPENBSD master manifest: #{error_text(e)}"
        end
      end

      def deployment_summary_receipt(problems, manifests, source)
        if problems.any?
          receipt("violation_found", reason: "deployment contract mismatch: #{problems.first(4).join("; ")}",
            findings: problems.first(30), evidence: { "manifests" => manifests })
        else
          receipt("assessed_clean", evidence: {
            "method" => "local deployment manifest, repository-contained script/root, and inventory parity checks",
            "manifests" => manifests,
            "source_sha256" => source["digest"],
            "live_deployment" => "not_measured; no deploy or remote mutation was performed",
          }, counts: { "manifest_entries" => manifests.size })
        end
      end

      def validate_repo_path(value, name, problems)
        text = value.to_s
        return unless text.empty? || text.start_with?("/") || text.split("/").include?("..")
          problems << "#{name} path is not repository-relative: #{text.inspect}"

      end

      # master's row in the deploy inventory must carry apps.yml's domain and port.
      def master_inventory_findings(inventory_path)
        row = master_inventory_row(inventory_path)
        metadata = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml")).dig("apps", "master")
        return [["OPENBSD deploy inventory has no master app"], nil] unless row.is_a?(Hash)
        return [["RAILS/apps.yml has no master app"], nil] unless metadata.is_a?(Hash)

        drift = %w[domain port].reject { |key| row[key].to_s == metadata[key].to_s }
        [drift.map { |key| "master: deploy inventory #{key} differs from RAILS/apps.yml" }, { "master" => row }]
      end

      def master_inventory_row(inventory_path)
        apps = Array(JSON.parse(File.read(inventory_path, encoding: "UTF-8"))["apps"])
        apps.find { |app| app["name"] == "master" }&.slice("name", "domain", "port")
      end

      def selected_apps(app_names)
        label = @target_label
        return app_names.map(&:to_s) if label == "RAILS" || label == "OPENBSD" ||
          label == "RAILS/__shared" || label.start_with?("RAILS/__shared/") ||
          label.start_with?("OPENBSD/")

        name = rails_target? && label != "RAILS" ? target_app_name : nil
        name && app_names.map(&:to_s).include?(name) ? [name] : []
      end

      public

      # The bounded no-follow target inventory, the FixPlan source manifest and
      # the discovery of safe target-scoped test runner commands from inventory
      # records.
      private

      def inventory_snapshot
        root = File.directory?(@target) ? @target : nil
        return { "status" => "inconclusive", "reason" => "target is not a directory", "records" => [] } unless root

        walk_target_inventory(root)
      rescue StandardError => e
        { "status" => "inconclusive", "reason" => "inventory failed: #{error_text(e)}", "records" => [] }
      end

      def walk_target_inventory(root)
        records = []
        ignored = []
        symlinks = 0
        pending = [root]
        until pending.empty?
          directory = pending.pop
          Dir.children(directory).sort.each do |name|
            record = inventory_record(pending, File.join(directory, name), ignored)
            next unless record

            symlinks += 1 if record[1] == "symlink"
            records << record
            return truncated_inventory(records, ignored, symlinks) if records.size > INVENTORY_CAP
          end
        end
        finished_inventory(records, ignored, symlinks)
      end

      def inventory_record(pending, path, ignored)
        relative_path = relative(path)
        stat = File.lstat(path)
        if stat.symlink?
          [relative_path, "symlink", stat.size]
        elsif stat.directory?
          inventory_directory_record(pending, path, relative_path, ignored)
        elsif stat.file?
          [relative_path, "file", stat.size]
        else
          [relative_path, "other", stat.size]
        end
      end

      def inventory_directory_record(pending, path, relative_path, ignored)
        if ignored_directory?(relative_path)
          ignored << relative_path
          return
        end

        pending << path
        [relative_path, "directory", 0]
      end

      def truncated_inventory(records, ignored, symlinks)
        {
          "status" => "inconclusive", "reason" => "target inventory exceeded cap #{INVENTORY_CAP}",
          "records" => records.first(INVENTORY_CAP), "truncated" => true,
          "files" => records.count { |row| row[1] == "file" },
          "directories" => records.count { |row| row[1] == "directory" },
          "symlinks" => symlinks, "ignored_directories" => ignored.first(100),
          "digest" => digest_json(records.first(INVENTORY_CAP)),
        }
      end

      def finished_inventory(records, ignored, symlinks)
        records.sort_by!(&:first)
        {
          "status" => "captured",
          "records" => records,
          "files" => records.count { |row| row[1] == "file" },
          "directories" => records.count { |row| row[1] == "directory" },
          "symlinks" => symlinks,
          "ignored_directories" => ignored.sort,
          "truncated" => false,
          "digest" => digest_json(records),
        }
      end

      def ignored_directory?(relative_path)
        parts = relative_path.split("/")
        nested, single = IGNORED_DIRECTORIES.partition { |entry| entry.include?("/") }
        parts.any? { |part| single.include?(part) } ||
          nested.any? { |entry| parts.each_cons(entry.count("/") + 1).include?(entry.split("/")) }
      end

      def source_manifest
        rows = []
        failures = []
        Array(@plan&.sources).each { |item| collect_source_manifest_row(item, rows, failures) }
        summarize_source_manifest(rows, failures)
      rescue StandardError => e
        { "status" => "inconclusive", "reason" => "source manifest failed: #{error_text(e)}", "digest" => "" }
      end

      def collect_source_manifest_row(item, rows, failures)
        path = File.expand_path(item.path, @root)
        unless File.file?(path) && !File.symlink?(path)
          failures << relative(path)
          return
        end

        before = File.stat(path)
        sha = Digest::SHA256.file(path).hexdigest
        after = File.stat(path)
        if stat_signature(before) != stat_signature(after) || after.size != item.bytes || sha != item.sha256
          failures << relative(path)
          return
        end
        rows << [item.path, sha, after.size]
      rescue StandardError
        failures << item.path
      end

      def summarize_source_manifest(rows, failures)
        rows.sort_by!(&:first)
        digest = digest_json(rows)
        expected = @plan&.source_digest.to_s
        status = failures.empty? && !expected.empty? && digest == expected ? "captured" : "inconclusive"
        {
          "status" => status,
          "digest" => digest,
          "expected_digest" => expected,
          "source_count" => rows.size,
          "failures" => failures.first(30),
          "reason" => status == "captured" ? nil : "FixPlan source bytes or metadata no longer match: #{failures.first(4).join(", ")}",
        }.compact
      end

      def test_commands(inventory)
        paths = inventory["records"].filter_map { |row| row[0] if row[1] == "file" }
        label = @target_label
        return web_test_commands(label, paths) if web_target?
        return master_test_commands(label, paths) if label == "MASTER" || label.start_with?("MASTER/")
        return openbsd_test_commands(label, paths) if label == "OPENBSD" || label.start_with?("OPENBSD/")
        return studio_test_commands(label, paths) if label == "STUDIO" || label.start_with?("STUDIO/")
        return rails_test_commands(label, paths) if label == "RAILS" || label.start_with?("RAILS/")

        []
      end

      def master_test_commands(_label, paths)
        tests = paths.any? { |path| path.start_with?("MASTER/test/") || path.start_with?("MASTER/tools/test/") }
        return [] unless tests && File.file?(File.join(@root, "MASTER", "Rakefile"))

        [{ label: "MASTER rake test", argv: [RbConfig.ruby, "-S", "rake", "test"], chdir: File.join(@root, "MASTER") }]
      end

      def openbsd_test_commands(_label, paths)
        return [] unless paths.any? { |path| path.start_with?("OPENBSD/test/") } && File.file?(File.join(@root, "OPENBSD", "test", "run_all.rb"))

        [{ label: "OPENBSD test/run_all.rb", argv: [RbConfig.ruby, "test/run_all.rb"], chdir: File.join(@root, "OPENBSD") }]
      end

      def studio_test_commands(_label, paths)
        return [] unless paths.any? { |path| path.start_with?("STUDIO/replicate/test/") } && File.file?(File.join(@root, "STUDIO", "replicate", "Rakefile"))

        [{ label: "STUDIO rake test", argv: [RbConfig.ruby, "-S", "rake", "test"], chdir: File.join(@root, "STUDIO") }]
      end

      def rails_test_commands(label, paths)
        commands = []
        rails_root = File.join(@root, "RAILS")
        if label == "RAILS" && paths.any? { |path| path.start_with?("RAILS/test/") } &&
           File.file?(File.join(rails_root, "test", "run_all.rb"))
          commands << { label: "RAILS test/run_all.rb", argv: [RbConfig.ruby, "test/run_all.rb"], chdir: rails_root }
        end

        rails_app_test_targets(label, paths).each do |name, app_dir|
          commands << {
            label: "RAILS #{name} bin/rails test",
            argv: [RbConfig.ruby, "bin/rails", "test"],
            chdir: app_dir,
            env: { "RAILS_ENV" => "test" },
          }
        end
        commands
      end

      # MASTER/web is a Rails app inside MASTER: its suite is bin/rails test, not MASTER's rake.
      def web_test_commands(label, paths)
        argv = [RbConfig.ruby, "bin/rails", "test"]
        rails_app_test_targets(label, paths).map do |_name, app_dir|
          { label: "MASTER/web bin/rails test", argv:, chdir: app_dir, env: { "RAILS_ENV" => "test" } }
        end
      end

      def rails_app_test_targets(label, paths)
        return [] unless rails_target?

        app_names = []
        if label == "RAILS"
          app_names = %w[amber brgen bsdports]
        elsif label == "RAILS/__shared" || label.start_with?("RAILS/__shared/")
          app_names = %w[amber brgen bsdports]
        else
          app_names = [target_app_name]
        end
        app_names.filter_map do |name|
          app_dir = app_dir(name)
          test_path = File.join(app_dir, "test")
          rails_bin = File.join(app_dir, "bin", "rails")
          next unless File.directory?(test_path) && File.file?(rails_bin) && !File.symlink?(rails_bin)
          next unless label == "RAILS" || label == "RAILS/__shared" || label.start_with?("RAILS/__shared/") ||
            paths.any? { |path| path.start_with?("#{relative(app_dir)}/") }

          [name, app_dir]
        end
      end

      public

      # The runtime surface receipt: language parser probes (Ruby, ERB,
      # JavaScript, shell) plus safe Rails application boot probes, run under a
      # shared deadline and never through a shell.
      private

      RUBY_SYNTAX_PROBE = <<~'RUBY'.freeze
        ARGV.each do |path|
          begin
            if defined?(RubyVM::InstructionSequence)
              RubyVM::InstructionSequence.compile_file(path)
            elsif !require("ripper") || !Ripper.sexp(File.read(path))
              raise SyntaxError, "parse failed"
            end
          rescue StandardError, ScriptError => error
            warn "#{path}: #{error.class}: #{error.message}"
            exit 1
          end
        end
      RUBY
      ERB_SYNTAX_PROBE = <<~'RUBY'.freeze
        require "erb"
        ARGV.each do |path|
          begin
            source = ERB.new(File.read(path), trim_mode: "-").src
            if defined?(RubyVM::InstructionSequence)
              RubyVM::InstructionSequence.compile(source, path)
            elsif !require("ripper") || !Ripper.sexp(source)
              raise SyntaxError, "parse failed"
            end
          rescue StandardError, ScriptError => error
            warn "#{path}: #{error.class}: #{error.message}"
            exit 1
          end
        end
      RUBY
      private_constant :RUBY_SYNTAX_PROBE, :ERB_SYNTAX_PROBE

      def runtime_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        runtime_paths = runtime_paths_for(RUNTIME_EXTENSIONS)
        return receipt("not_applicable", reason: "target contains no supported runtime source files") if runtime_paths.empty?
        unless @run_expensive
          return receipt("inconclusive", reason: "runtime probes deferred until a clean scanner candidate pass",
            evidence: { "source_sha256" => source["digest"] })
        end

        results = runtime_probe_outcomes(command_deadline(RUNTIME_TIMEOUT))
        runtime_receipt_result(source, results)
      rescue StandardError => e
        receipt("inconclusive", reason: "runtime probe failed: #{error_text(e)}")
      end

      def runtime_paths_for(extensions)
        @plan.sources.map(&:path).select { |path| extensions.include?(File.extname(path).downcase) }
      end

      def runtime_probe_outcomes(deadline)
        failures = []
        unavailable = []
        checked = Hash.new(0)
        runtime_ruby_probe(runtime_paths_for(%w[.rb .rake .gemspec]), deadline, checked, failures, unavailable)
        runtime_erb_probe(runtime_paths_for([".erb"]), deadline, checked, failures, unavailable)
        runtime_javascript_probe(deadline, checked, failures, unavailable)
        shell_groups = runtime_shell_groups
        runtime_shell_probes(shell_groups, deadline, checked, failures, unavailable)
        boot = rails_runtime_probes(deadline)
        failures.concat(boot[:failures])
        unavailable.concat(boot[:unavailable])
        { failures:, unavailable:, checked:, boot:, shell_groups: }
      end

      def runtime_ruby_probe(paths, deadline, checked, failures, unavailable)
        return if paths.empty?

        command = [RbConfig.ruby, "-e", RUBY_SYNTAX_PROBE, *paths.map { |path| File.expand_path(path, @root) }]
        outcome = execute_command(command, chdir: @root, deadline:)
        checked["ruby"] = paths.size
        if outcome["status"] == "failed"
          failures << outcome.merge("language" => "ruby")
        elsif outcome["status"] == "inconclusive"
          unavailable << "Ruby syntax probe unavailable or timed out"
        end
      end

      def runtime_erb_probe(paths, deadline, checked, failures, unavailable)
        return if paths.empty?
        return unavailable << "ERB syntax probe exceeded runtime budget" unless deadline_remaining(deadline).positive?

        outcome = execute_command(
          [RbConfig.ruby, "-e", ERB_SYNTAX_PROBE, *paths.map { |path| File.expand_path(path, @root) }],
          chdir: @root, deadline:
        )
        checked["erb"] = paths.size
        if outcome["status"] == "failed"
          failures << outcome.merge("language" => "erb")
        elsif outcome["status"] == "inconclusive"
          unavailable << "ERB probe unavailable or timed out"
        end
      end

      def runtime_javascript_probe(deadline, checked, failures, unavailable)
        typed_paths = runtime_paths_for(%w[.jsx .ts .tsx])
        unless typed_paths.empty?
          unavailable << "#{typed_paths.size} TypeScript/JSX file(s) need a project-aware parser; Node --check is not evidence for these formats"
        end
        paths = runtime_paths_for(%w[.js .mjs .cjs])
        return if paths.empty?

        node = executable_path("node")
        return unavailable << "#{paths.size} JavaScript file(s) found but Node.js is unavailable" unless node

        runtime_javascript_file_probes(paths, node, deadline, checked, failures, unavailable)
      end

      def runtime_javascript_file_probes(paths, node, deadline, checked, failures, unavailable)
        paths.each do |path|
          break if deadline_remaining(deadline) <= 0

          outcome = execute_command([node, "--check", File.expand_path(path, @root)], chdir: @root, deadline:)
          checked["javascript"] += 1
          if outcome["status"] == "failed"
            failures << outcome.merge("language" => "javascript", "file" => path)
          elsif outcome["status"] == "inconclusive"
            unavailable << "#{path}: JavaScript parser unavailable or timed out"
          end
        end
        if checked["javascript"] < paths.size
          unavailable << "#{paths.size - checked["javascript"]} JavaScript file(s) not parsed before budget"
        end
      end

      def runtime_shell_groups
        {
          "sh" => %w[.sh .bash],
          "ksh" => [".ksh"],
          "zsh" => [".zsh"],
        }
      end

      def runtime_shell_probes(groups, deadline, checked, failures, unavailable)
        groups.each do |shell, extensions|
          runtime_shell_probe(shell, extensions, deadline, checked, failures, unavailable)
        end
      end

      def runtime_shell_probe(shell, extensions, deadline, checked, failures, unavailable)
        paths = runtime_paths_for(extensions)
        return if paths.empty?

        executable = executable_path(shell)
        unless executable
          unavailable << "#{paths.size} #{shell} script(s) found but #{shell} is unavailable"
          return
        end
        runtime_shell_file_probes(shell, executable, paths, deadline, checked, failures, unavailable)
      end

      def runtime_shell_file_probes(shell, executable, paths, deadline, checked, failures, unavailable)
        paths.each do |path|
          break if deadline_remaining(deadline) <= 0

          outcome = execute_command([executable, "-n", File.expand_path(path, @root)], chdir: @root, deadline:)
          checked[shell] += 1
          if outcome["status"] == "failed"
            failures << outcome.merge("language" => shell, "file" => path)
          elsif outcome["status"] == "inconclusive"
            unavailable << "#{path}: #{shell} parser unavailable or timed out"
          end
        end
        unavailable << "#{paths.size - checked[shell]} #{shell} script(s) not parsed before budget" if checked[shell] < paths.size
      end

      def runtime_receipt_result(source, results)
        details = runtime_receipt_details(source, results)
        return receipt("violation_found", reason: "one or more runtime syntax or boot probes failed",
          evidence: details, findings: results[:failures].first(20)) if results[:failures].any?
        return receipt("inconclusive", reason: results[:unavailable].first(4).join("; "), evidence: details) if results[:unavailable].any?

        receipt("assessed_clean", evidence: details, counts: {
          "ruby" => results[:checked]["ruby"],
          "erb" => results[:checked]["erb"],
          "javascript" => results[:checked]["javascript"],
          "shell" => results[:shell_groups].keys.sum { |key| results[:checked][key] },
          "rails_boots" => results[:boot][:checked].size,
        })
      end

      def runtime_receipt_details(source, results)
        {
          "method" => "language parser checks plus safe Rails application boot probes where applicable",
          "source_sha256" => source["digest"],
          "checked" => results[:checked],
          "rails_boots" => results[:boot][:checked],
          "failures" => results[:failures].first(20).map { |row| row.slice("language", "file", "status", "exit_status", "message") },
          "unavailable" => results[:unavailable].first(20),
        }
      end

      def rails_runtime_probes(deadline)
        return { failures: [], unavailable: [], checked: [] } unless rails_target?
        return { failures: [], unavailable: ["Rails boot probes deferred until a clean scanner candidate pass"], checked: [] } unless @run_expensive

        rails_runtime_probe_results(deadline)
      end

      def rails_runtime_probe_results(deadline)
        failures = []
        unavailable = []
        checked = []
        rails_runtime_app_targets(unavailable).each do |name, app_dir|
          rails_app_boot_probe(name, app_dir, deadline, checked, failures, unavailable)
        end
        { failures:, unavailable:, checked: }
      end

      def rails_runtime_app_targets(unavailable)
        app_names = if @target_label == "RAILS" || @target_label == "RAILS/__shared" || @target_label.start_with?("RAILS/__shared/")
                      %w[amber brgen bsdports]
                    else
                      [target_app_name]
                    end
        app_names.filter_map do |name|
          app_dir = app_dir(name)
          runner = File.join(app_dir, "bin", "rails")
          if File.directory?(app_dir) && File.file?(runner) && !File.symlink?(runner)
            [name, app_dir]
          else
            unavailable << "#{name}: Rails app directory or bin/rails launcher is unavailable"
            nil
          end
        end
      end

      def rails_app_boot_probe(name, app_dir, deadline, checked, failures, unavailable)
        if deadline_remaining(deadline) <= 0
          unavailable << "Rails app boot budget exhausted before #{name}" unless checked.include?(name)
          return
        end

        row = execute_command(
          [RbConfig.ruby, "bin/rails", "runner", "puts Rails.application.routes.routes.size"],
          chdir: app_dir, env: { "RAILS_ENV" => "test" }, deadline:,
        )
        checked << name
        if row["status"] == "failed"
          failures << row.merge("app" => name)
        elsif row["status"] == "inconclusive"
          unavailable << "#{name}: Rails boot probe timed out or was unavailable"
        end
      end

      def executable_path(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }.
          find { |candidate| File.file?(candidate) && File.executable?(candidate) }
      end

      public

      # The command runner every probe and test receipt goes through: popen3
      # with a process group, a hard deadline, output draining and the
      # group-signalled shutdown that never falls back to a numeric child PID.
      private

      def execute_command(argv, chdir:, env: {}, deadline:)
        command = Array(argv).map(&:to_s)
        return { "status" => "inconclusive", "message" => "command deadline exhausted", "timed_out" => true } if deadline_remaining(deadline) <= 0

        run_command_with_limits(command, chdir:, env:, deadline:)
      rescue Errno::ENOENT => e
        { "status" => "inconclusive", "message" => "executable unavailable: #{error_text(e)}" }
      rescue StandardError => e
        { "status" => "inconclusive", "message" => "command runner failed: #{error_text(e)}" }
      end

      def run_command_with_limits(command, chdir:, env:, deadline:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timeout = [DEFAULT_COMMAND_TIMEOUT, deadline_remaining(deadline)].min
        stdout = +""
        stderr = +""
        state = spawn_command_process(command, chdir:, env:, started:, timeout:, stdout:, stderr:)
        command_outcome(command, state, started:, timeout:, stdout:, stderr:)
      end

      def spawn_command_process(command, chdir:, env:, started:, timeout:, stdout:, stderr:)
        state = { timed_out: false, termination_confirmed: true, status: nil }

        Open3.popen3(Master::Io::ProcessSpawn.environment(ENV.to_h.merge(env.transform_keys(&:to_s).transform_values(&:to_s))), *command, chdir:, pgroup: true) do |stdin, out, err, wait_thr|
          stdin.close
          stdout_reader = Thread.new { drain_output(out, stdout) }
          stderr_reader = Thread.new { drain_output(err, stderr) }
          supervise_command_process(wait_thr, stdout_reader, stderr_reader, started + timeout, state, out, err)
          state[:status] = wait_thr.value unless wait_thr.alive?
        end

        state
      end

      def supervise_command_process(wait_thr, stdout_reader, stderr_reader, deadline, state, out, err)
        await_process_or_deadline(wait_thr, stdout_reader, stderr_reader, deadline, state)
        terminate_command_process(wait_thr, stdout_reader, stderr_reader, out, err, state) if state[:timed_out]
      end

      def await_process_or_deadline(wait_thr, stdout_reader, stderr_reader, deadline, state)
        loop do
          break unless wait_thr.alive? || stdout_reader.alive? || stderr_reader.alive?

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            state[:timed_out] = true
            break
          end

          if wait_thr.alive?
            wait_thr.join([remaining, 0.05].min)
          else
            sleep([remaining, 0.01].min)
          end
        end
      end

      def terminate_command_process(wait_thr, stdout_reader, stderr_reader, out, err, state)
        confirmed = stop_process_group(wait_thr.pid)
        wait_thr.join(2)
        # wait_thr is the direct child this method spawned. If group signalling
        # was denied, KILL that exact still-owned child; never fall back to a
        # numeric PID after ESRCH or after the wait handle has completed.
        kill_owned_child(wait_thr) if wait_thr.alive?
        wait_thr.join(2) if wait_thr.alive?
        confirmed &&= !wait_thr.alive? && !process_group_alive?(wait_thr.pid)
        terminate_command_readers(out, stdout_reader, err, stderr_reader)
        confirmed &&= !stdout_reader.alive? && !stderr_reader.alive?
        state[:termination_confirmed] = confirmed
      end

      def terminate_command_readers(out, stdout_reader, err, stderr_reader)
        [[out, stdout_reader], [err, stderr_reader]].each do |io, reader|
          reader.join(0.2)
          next unless reader.alive?

          io.close rescue nil
          reader.kill
          reader.join(0.2)
        end
      end

      def command_outcome(command, state, started:, timeout:, stdout:, stderr:)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        code = state[:status]&.exitstatus
        {
          "status" => command_outcome_status(state, code),
          "exit_status" => code,
          "timed_out" => state[:timed_out],
          "termination_confirmed" => state[:termination_confirmed],
          "duration_ms" => elapsed,
          "stdout_sha256" => Digest::SHA256.hexdigest(stdout),
          "stderr_sha256" => Digest::SHA256.hexdigest(stderr),
          "message" => command_outcome_message(state, code, timeout, stdout, stderr),
          "command" => command.first(4).map { |item| File.basename(item) },
        }.compact
      end

      def command_outcome_status(state, code)
        if state[:timed_out]
          "inconclusive"
        elsif code == 0
          "passed"
        else
          "failed"
        end
      end

      def command_outcome_message(state, code, timeout, stdout, stderr)
        if state[:timed_out]
          suffix = state[:termination_confirmed] ? "process group stopped" : "process-group shutdown unverified"
          "command timed out after #{timeout.round(1)}s; #{suffix}"
        elsif code != 0
          safe_text((stderr.empty? ? stdout : stderr).lines.last(3).join(" ").strip, 220)
        end
      end

      def drain_output(io, buffer = +"")
        loop do
          chunk = io.readpartial(4096)
          buffer << chunk if buffer.bytesize < MAX_PROCESS_OUTPUT
        end
      rescue EOFError, IOError
        buffer
      end

      def stop_process_group(pid, term_grace: 0.25, kill_grace: 2.0)
        group = Integer(pid)
        return false unless group.positive?
        return false if group == Process.getpgrp
        return true unless process_group_alive?(group)

        signal_group("TERM", group)
        return true if wait_for_group_exit(group, term_grace)

        signal_group("KILL", group)
        wait_for_group_exit(group, kill_grace)
      rescue ArgumentError, TypeError
        false
      end

      def signal_group(signal, group)
        Process.kill(signal, -group)
        true
      rescue Errno::ESRCH
        true
      rescue Errno::EPERM
        false
      end

      def wait_for_group_exit(group, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          return true unless process_group_alive?(group)
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.025
        end
      end

      def process_group_alive?(group)
        Process.kill(0, -group)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      def kill_owned_child(wait_thr)
        return false unless wait_thr.alive?

        Process.kill("KILL", wait_thr.pid)
        true
      rescue Errno::ESRCH
        true
      rescue Errno::EPERM
        false
      end

      def command_deadline(limit)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        plan_remaining = begin
          @plan.deadline_at ? Time.iso8601(@plan.deadline_at) - Time.now : limit
        rescue StandardError
          limit
        end
        now + [[limit, plan_remaining].min, 0].max
      end

      def deadline_remaining(deadline)
        deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      public

      SCHEMA_VERSION = 1
      INVENTORY_CAP = Integer(ENV.fetch("MASTER_FIX_SURFACE_INVENTORY_CAP", "30000"))
      MAX_PROCESS_OUTPUT = 16_384
      DEFAULT_COMMAND_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_COMMAND_TIMEOUT_S", "180"))
      TEST_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_TEST_TIMEOUT_S", "600"))
      RUNTIME_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_RUNTIME_TIMEOUT_S", "180"))
      IGNORED_DIRECTORIES = %w[
        .git .master .bundle node_modules vendor/bundle tmp log storage coverage
        .cache .sass-cache
      ].freeze
      MEDIA_EXTENSIONS = %w[
        .png .jpg .jpeg .gif .webp .avif .svg .ico .bmp .tif .tiff .pdf
        .wav .mp3 .m4a .aac .ogg .flac .mp4 .mov .webm .woff .woff2 .ttf .otf
      ].freeze
      RUNTIME_EXTENSIONS = %w[
        .rb .rake .gemspec .erb .js .mjs .cjs .ts .tsx .jsx
        .sh .bash .ksh .zsh
      ].freeze

      SOURCE_TYPES = %w[file directory symlink other].freeze
      COMPLETE_STATUSES = %w[assessed_clean not_applicable].freeze
      SURFACES = %w[
        repository_tree directories file_names paths cross_file media_assets compiled_assets
        rendered_ui interactive_behavior tests runtime deployment
      ].freeze

      def self.capture(root:, target:, plan:, files:, visual_result: nil, reference_graph: nil,
                       cache: {}, run_expensive: false)
        new(
          root:, target:, plan:, files:, visual_result:, reference_graph:, cache:, run_expensive:,
        ).capture
      end

      def initialize(root:, target:, plan:, files:, visual_result:, reference_graph:, cache:, run_expensive:)
        @root = File.expand_path(root)
        @target = File.expand_path(target.to_s, @root)
        @plan = plan
        @files = Array(files).map { |path| File.expand_path(path.to_s, @root) }.uniq.sort
        @visual_result = visual_result
        @reference_graph = reference_graph
        @cache = cache
        @run_expensive = run_expensive == true
        @target_label = relative(@target)
        @tree = @target_label.split("/", 2).first
      end

      def capture
        source_before, inventory_before = capture_baseline
        receipts = initial_receipts(inventory_before, source_before)
        source_after, inventory_after = capture_current_state
        stable = surface_stability(source_before, source_after, inventory_before, inventory_after)
        mark_unstable_receipts(receipts, source_after, inventory_after) unless stable

        complete = stable && receipts.values.all? { |receipt| COMPLETE_STATUSES.include?(receipt["status"]) }
        compact = compact_surface_rows(receipts)
        report_digest = surface_report_digest(compact, inventory_before)
        capture_report(receipts, compact, complete, report_digest,
          source_before:, source_after:, inventory_before:, inventory_after:, stable:)
      rescue StandardError => e
        failed_report(e)
      end

      def capture_baseline
        source = source_manifest
        inventory = inventory_snapshot
        @current_inventory_digest = inventory["digest"]
        [source, inventory]
      end

      def capture_current_state
        [source_manifest, inventory_snapshot]
      end

      private

      def cached(name)
        key = [name.to_s, @plan&.source_digest.to_s, @plan&.scope_digest.to_s, @current_inventory_digest.to_s]
        return json_safe(@cache[key]) if @cache.key?(key)

        result = yield
        @cache[key] = result if result.is_a?(Hash) && %w[assessed_clean violation_found not_applicable].include?(result["status"].to_s)
        result
      rescue StandardError => e
        receipt("inconclusive", reason: "#{name} probe failed: #{error_text(e)}")
      end

      def initial_receipts(inventory, source)
        receipts = {}
        receipts["repository_tree"] = tree_receipt(inventory, source)
        receipts["directories"] = directory_receipt(inventory, source)
        receipts["file_names"] = file_name_receipt(inventory, source)
        receipts["paths"] = path_receipt(inventory, source)
        receipts["cross_file"] = cross_file_receipt(inventory, source)
        receipts["media_assets"] = media_receipt(inventory, source)
        receipts["compiled_assets"] = compiled_asset_receipt(inventory, source)
        receipts["rendered_ui"] = rendered_ui_receipt
        receipts["interactive_behavior"] = interactive_receipt
        receipts["tests"] = cached("tests") { test_receipt(inventory, source) }
        receipts["runtime"] = cached("runtime") { runtime_receipt(inventory, source) }
        receipts["deployment"] = deployment_receipt(inventory, source)
        receipts
      end

      def surface_stability(source_before, source_after, inventory_before, inventory_after)
        source_before["digest"] == source_after["digest"] &&
          inventory_before["digest"] == inventory_after["digest"] &&
          source_before["status"] == "captured" && source_after["status"] == "captured" &&
          inventory_before["status"] == "captured" && inventory_after["status"] == "captured"
      end

      def mark_unstable_receipts(receipts, source_after, inventory_after)
        reason = "FixPlan source or target inventory changed during surface assessment"
        receipts.each do |name, receipt|
          next if receipt["status"] == "not_applicable"

          receipts[name] = receipt.merge(
            "status" => "inconclusive",
            "reason" => reason,
            "observed_after" => {
              "source_digest" => source_after["digest"],
              "inventory_digest" => inventory_after["digest"],
            },
          )
        end
      end

      def compact_surface_rows(receipts)
        receipts.sort.to_h do |name, receipt|
          [name, {
            "status" => receipt["status"],
            "reason" => receipt["reason"],
            "evidence_sha256" => receipt["evidence_sha256"],
            "counts" => receipt["counts"],
          }.compact]
        end
      end

      def surface_report_digest(compact, inventory)
        Digest::SHA256.hexdigest(JSON.generate(
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "inventory_digest" => inventory["digest"],
          "surface_rows" => compact.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
        ))
      end

      def capture_report(receipts, compact, complete, report_digest,
                         source_before:, source_after:, inventory_before:, inventory_after:, stable:)
        {
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "target_absolute" => @target,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "scope_digest" => @plan&.scope_digest,
          "source_manifest" => capture_source_manifest_section(source_before, source_after, stable),
          "inventory" => capture_inventory_section(inventory_before, inventory_after),
          "surfaces" => compact,
          "details" => receipts,
          "complete" => complete,
          "digest" => report_digest,
        }
      end

      def capture_source_manifest_section(source_before, source_after, stable)
        source_before.merge(
          "verified_after_assessment" => stable,
          "digest_after_assessment" => source_after["digest"],
        )
      end

      def capture_inventory_section(inventory_before, inventory_after)
        {
          "status" => inventory_before["status"],
          "digest" => inventory_before["digest"],
          "files" => inventory_before["files"],
          "directories" => inventory_before["directories"],
          "symlinks" => inventory_before["symlinks"],
          "ignored_directories" => inventory_before["ignored_directories"],
          "truncated" => inventory_before["truncated"],
          "sample" => inventory_before["records"].first(80),
          "after_digest" => inventory_after["digest"],
        }
      end

      def receipt(status, reason: nil, evidence: {}, findings: [], counts: {})
        row = {
          "status" => status.to_s,
          "reason" => reason.to_s.empty? ? nil : safe_text(reason, 240),
          "evidence" => json_safe(evidence),
          "findings" => json_safe(Array(findings).first(30)),
          "counts" => json_safe(counts),
          "evidence_sha256" => digest_json(json_safe(evidence)),
        }
        row.compact
      end

      def captured?(inventory, source)
        inventory["status"] == "captured" && source["status"] == "captured"
      end

      def stat_signature(stat)
        [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
      end

      def read_stable(path)
        before = File.stat(path)
        body = File.read(path, encoding: "UTF-8")
        after = File.stat(path)
        return unless stat_signature(before) == stat_signature(after)

        body
      rescue StandardError
        nil
      end

      def relative(path)
        File.expand_path(path.to_s, @root).delete_prefix("#{@root}/")
      end

      def digest_json(value) = Digest::SHA256.hexdigest(JSON.generate(value))

      # Plain JSON values with string keys. Called by the cache and every receipt and never
      # defined, so building any surface receipt raised NoMethodError and the assessment
      # matrix stage failed on every pass.
      def json_safe(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, json_safe(item)] }
        when Array then value.map { |item| json_safe(item) }
        when String, Integer, Float, true, false, nil then value
        else value.to_s
        end
      end

      def safe_text(value, limit = 240)
        value.to_s.gsub(/\s+/, " ").strip[0, limit].to_s
          .gsub(/(?i)(password|passwd|token|secret|authorization)(\s*[:=]\s*)[^\s,;]+/, '\1\2[redacted]')
      end

      def error_text(error) = safe_text("#{error.class}: #{error.message}", 180)

      def row_value(hash, key)
        return unless hash.is_a?(Hash)

        hash[key] || hash[key.to_sym]
      end

      def row_status(hash, key) = row_value(hash, key).to_s

      def result_value(result)
        result.respond_to?(:value!) ? result.value! : nil
      rescue StandardError
        nil
      end

      def failed_report(error)
        reason = "surface evidence failed: #{error_text(error)}"
        rows = SURFACES.to_h { |name| [name, receipt("inconclusive", reason:)] }
        compact = failed_compact_rows(rows)
        {
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "target_absolute" => @target,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "source_manifest" => { "status" => "inconclusive", "reason" => reason },
          "inventory" => { "status" => "inconclusive", "sample" => [] },
          "surfaces" => compact,
          "details" => rows,
          "complete" => false,
          "digest" => failed_report_digest(compact),
        }
      end

      def failed_compact_rows(rows)
        rows.sort.to_h { |name, row| [name, row.slice("status", "reason", "evidence_sha256", "counts").compact] }
      end

      def failed_report_digest(compact)
        digest_json(
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "inventory_digest" => nil,
          "surface_rows" => compact.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
        )
      end

      def rails_target? = @target_label == "RAILS" || @target_label.start_with?("RAILS/") || web_target?

      # MASTER/web is master's Rails app, registered in RAILS/apps.yml like the others.
      def web_target? = @target_label == "MASTER/web" || @target_label.start_with?("MASTER/web/")

      def target_app_name = web_target? ? "master" : @target_label.delete_prefix("RAILS/").split("/", 2).first

      def app_dir(name) = File.join(@root, name == "master" ? "MASTER/web" : "RAILS/#{name}")
    end
  end
end
