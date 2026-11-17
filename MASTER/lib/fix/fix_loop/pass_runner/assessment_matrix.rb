# frozen_string_literal: true

require_relative "../../kernel"
require_relative "../../task_contract"

# This file is also imported directly by assessment tests. Reuse the canonical
# class object without recursively loading the full convergence graph.
module Master
  module Fix
    remove_const(:FixLoop) if autoload?(:FixLoop, false)
    const_set(:FixLoop, Kernel::ConvergenceAdapter) unless const_defined?(:FixLoop, false)

    # The direct import can reach this file before pass_runner.rb has defined
    # the class. Opening `class PassRunner` below would then fire the adapter's
    # const_missing, which loads the full convergence graph and re-enters this
    # file with AssessmentMatrix still undefined — the NameError the direct
    # import exists to avoid. Declare the same read-only stub lifecycle.rb
    # uses for the adapter itself; pass_runner.rb fills the body on real boot.
    FixLoop.send(:remove_const, :PassRunner) if FixLoop.autoload?(:PassRunner, false)
    FixLoop.const_set(:PassRunner, Class.new) unless FixLoop.const_defined?(:PassRunner, false)
  end
end

require "pathname"
require "set"
require_relative "../../four_stream_assessment"
require_relative "../../surface_evidence"

module Master
  module Fix
    class FixLoop
      class PassRunner
        # Runtime Law × stream × surface evidence and its source receipts.
        # This module owns measurement bookkeeping only; scanner, visual,
        # opportunity, run journal, and convergence implementations stay in
        # their existing owners.
        module AssessmentMatrix
          # Report concrete per-target adapter capability in the plan. Capability
          # inventory is not evidence of a successful measurement; missing assessors
          # still leave the completion ledger INCONCLUSIVE.
          def assessment_adapters(target:)
            visual_applicable = @visual_pass&.applicable?(target)
            visual = visual_applicable == true
            opportunities_applicable = @opportunity_pass&.applicable?(target)
            opportunities = opportunities_applicable == true
            assessment_adapter_capabilities(visual:, opportunities:)
          end

          def plan_refresh_failed!(error)
            stage_failures[:fix_plan] << "#{error.class}: #{error.message.to_s[0, 180]}"
            self
          end

          def plan_refresh_succeeded!
            stage_failures.delete(:fix_plan)
            self
          end

          # The matrix population is the canonical YAML Law catalogue projected
          # into executable definitions and Ruby detector adapters. Each Law ID
          # appears once; semantic and visual reviewers consume that same ID set.
          def begin_assessment_run(files:, plan:)
            assessment_reset_run_state!(plan)
            assessment_require_law_catalogue!
            info = {}
            assessment_canonical_law_info(info)
            assessment_scanner_law_info(info)
            opportunity_applicable = assessment_add_opportunity_law(info, plan)
            visual_applicable = assessment_add_visual_law(info, plan)
            assessment_activate_matrix(info, files, plan, opportunity_applicable, visual_applicable)
          rescue StandardError => e
            assessment_matrix_initialization_failed(e)
          end

          def assessment_matrix_initialization_failed(error)
            stage_failures[:assessment_matrix] << "#{error.class}: #{error.message.to_s[0, 180]}"
            @bus&.publish("fix_loop:assessment_matrix_init_failed",
              error_class: error.class.name, message: error.message)
            @assessment_ledger = nil
            self
          end

          LEXICAL_STREAM_FOR_MODE = { opportunity: :lexical_opportunities }.freeze

          # The lexical stream a detector's mode owns: an opportunity detector
          # owns lexical_opportunities and every other mode (violation,
          # mechanical, structural, semantic) lexical_violations.
          def assessment_lexical_ownership(mode, measurable:)
            owned = LEXICAL_STREAM_FOR_MODE.fetch(mode.to_sym, :lexical_violations)
            {
              mode: mode.to_sym,
              unowned_streams: (%i[lexical_violations lexical_opportunities] - [owned]).freeze,
              unmeasurable_streams: (measurable ? [] : [owned]).freeze,
            }
          end

          def assessment_law_id(law)
            value = law.respond_to?(:id) ? law.id : law
            value.to_s.strip
          rescue StandardError
            ""
          end

          def assessment_existing_law_id(info, value)
            needle = value.to_s
            info.keys.find { |candidate| candidate.casecmp?(needle) }
          end

          def assessment_plan_changed!(plan)
            return unless @assessment_ledger

            @assessment_mutex.synchronize do
              @assessment_ledger.invalidate!(
                iteration: @assessment_last_pass,
                reason: "fix plan changed to #{plan.digest}",
              )
              @assessment_plan = plan
              assessment_reset_plan_scope!(plan)
            end
            assessment_publish_generation(plan)
            self
          rescue StandardError => e
            stage_failures[:assessment_matrix] << "generation invalidation: #{e.class}: #{e.message.to_s[0, 150]}"
            self
          end

          def assessment_plan_refreshed!(plan)
            @assessment_mutex&.synchronize do
              @assessment_plan = plan
              @assessment_surface_presence = nil
              @assessment_surface_report = nil
              @assessment_surface_receipts = {}
              @assessment_surface_cache = {}
              @assessment_scope = plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort.freeze
              @assessment_file_coverage = nil
            end
            self
          rescue StandardError => e
            stage_failures[:assessment_matrix] << "plan metadata refresh: #{e.class}: #{e.message.to_s[0, 150]}"
            self
          end

          def assessment_matrix_status
            return :not_measured unless @assessment_ledger

            @assessment_ledger.clean? && @assessment_surface_report&.fetch("complete", false) == true ? :complete : :incomplete
          rescue StandardError => e
            stage_failures[:assessment_matrix] << "status read: #{e.class}: #{e.message.to_s[0, 150]}"
            :incomplete
          end

          def assessment_matrix_summary
            return {
              status: "not_measured",
              reason: "no scanner-backed Law population was available",
              file_coverage: assessment_file_coverage_summary,
            } unless @assessment_ledger

            @assessment_ledger.summary.merge(
              status: assessment_matrix_status.to_s,
              stream_coverage: @assessment_ledger.coverage(unmeasurable: @assessment_unmeasurable || Set.new),
              file_coverage: assessment_file_coverage_summary,
              surface_coverage_complete: @assessment_surface_report&.fetch("complete", false) == true,
              surface_coverage_digest: @assessment_surface_report&.fetch("digest", nil),
              surface_coverage: surface_coverage_summary,
            )
          rescue StandardError => e
            { status: "incomplete", reason: "matrix summary failed: #{e.class}: #{e.message.to_s[0, 150]}" }
          end

          def record_visual_group_result!(result)
            @assessment_visual_group_result = result.respond_to?(:to_h) ? result.to_h : result
            self
          end

          def record_improvement_assessment!(pass:, findings:, ideas: 0, restructures: 0,
                                              files_seen: 0, measured_files: 0, domains: [])
            @assessment_improvement_state ||= {
              evaluated_passes: 0, findings: 0, fixed: 0, ideas: 0, restructures: 0,
              files_seen: 0, measured_files: 0, domains: [],
            }
            @assessment_improvement_state[:evaluated_passes] += 1
            @assessment_improvement_state[:last_pass] = Integer(pass)
            # These fields describe the latest read-back assessment. Repeated
            # opportunities across passes are not distinct work items.
            @assessment_improvement_state[:findings] = Integer(findings)
            @assessment_improvement_state[:ideas] = Integer(ideas)
            @assessment_improvement_state[:restructures] = Integer(restructures)
            @assessment_improvement_state[:files_seen] = Integer(files_seen)
            @assessment_improvement_state[:measured_files] = Integer(measured_files)
            @assessment_improvement_state[:domains] = Array(domains).map(&:to_s).uniq.sort
            self
          end

          def record_improvement_repair!(findings:, fixed:)
            @assessment_improvement_state ||= { evaluated_passes: 0, findings: 0, fixed: 0, ideas: 0, restructures: 0 }
            @assessment_improvement_state[:fixed] += [Integer(fixed), Integer(findings)].min
            self
          end

          def assessment_quality_contract
            law_tags = (@assessment_law_info || {}).to_h do |id, info|
              law = info[:law] || info[:scanner_law]
              tags = law.respond_to?(:tags) ? Array(law.tags) : []
              [id, tags]
            end
            QualityContract.build(
              ledger: @assessment_ledger&.evidence_report,
              surface_report: @assessment_surface_report,
              target: @assessment_plan&.target,
              files: Array(@assessment_plan&.sources).map(&:path),
              lane: WorkLane.current,
              visual_groups: @assessment_visual_group_result,
              improvement: @assessment_improvement_state,
              law_tags:,
            )
          end

          def assessment_matrix_evidence
            {
              status: assessment_matrix_status.to_s,
              quality_contract: assessment_quality_contract,
              plan_digest: @assessment_plan&.digest,
              source_digest: @assessment_plan&.source_digest,
              **assessment_matrix_summary,
              surface_coverage: surface_coverage_summary,
            }
          rescue StandardError => e
            { status: "incomplete", reason: "matrix evidence failed: #{e.class}: #{e.message.to_s[0, 150]}" }
          end

          # Full report passed to RunJournal for durable, checksum-addressed storage.
          # It is deliberately not embedded in the bounded terminal history.
          def assessment_matrix_artifact
            return assessment_unmeasured_artifact unless @assessment_ledger

            @assessment_mutex.synchronize do
              {
                schema_version: 3,
                status: (assessment_matrix_status == :complete ? "complete" : "incomplete"),
                **assessment_plan_digest_fields,
                surface_coverage: @assessment_surface_report,
                file_coverage: @assessment_file_coverage || assessment_file_coverage_summary,
                ledger: @assessment_ledger.evidence_report,
                quality_contract: assessment_quality_contract,
              }
            end
          rescue StandardError => e
            assessment_artifact_failure(e)
          end

          private

          def assessment_adapter_availability(pass, applicable, available)
            return "unavailable" if pass.nil?
            return available if applicable

            "not_applicable_to_target"
          end

          def assessment_adapter_capabilities(visual:, opportunities:)
            {
              "whole_file" => @scan_phase ? "scanner" : "unavailable",
              "paths" => @scanner.respond_to?(:scan) ? "scanner" : "unavailable",
              "lines" => @scanner.respond_to?(:scan) ? "scanner" : "unavailable",
              "syntax_tree" => @scanner.respond_to?(:scan) ? "language_dispatch" : "unavailable",
              "structured_data" => @scanner.respond_to?(:scan) ? "scanner_path_filter" : "unavailable",
              "cross_file" => @reference_graph&.respond_to?(:build) ? "reference_graph" : "unavailable",
              "lexical_opportunities" => assessment_adapter_availability(@opportunity_pass, opportunities, "opportunity_pass"),
              "semantic_violations" => @scan_phase&.semantic_full? ? "full_semantic_mode" : "sampled_or_budgeted",
              "semantic_opportunities" => @council&.respond_to?(:improve) ? "bounded_council" : "unavailable",
              "rendered_ui" => assessment_adapter_availability(@visual_pass, visual, "visual_pass"),
              "interactive_behavior" => assessment_adapter_availability(@visual_pass, visual, "browser_journeys"),
              "tests" => "target_specific_runner_only",
              "runtime" => "target_specific_probe_only",
              "deployment" => "external_validation_not_universal",
            }.freeze
          end

          def assessment_reset_run_state!(plan)
            @assessment_plan = plan
            @assessment_surface_cache = {}
            @assessment_surface_report = nil
            @assessment_surface_receipts = {}
            @assessment_ledger = nil
            @assessment_observation = nil
            @assessment_law_info = nil
            @assessment_unclassified = []
            @assessment_unmeasurable = Set.new
            @assessment_last_pass = 0
            @assessment_visual_group_result = nil
            @assessment_improvement_state = {
              evaluated_passes: 0, findings: 0, fixed: 0, ideas: 0, restructures: 0,
              files_seen: 0, measured_files: 0, domains: [],
            }
          end

          def assessment_require_law_catalogue!
            require File.join(Master::ROOT, "law", "definition") unless defined?(::Law::Definition)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
            require File.join(Master::ROOT, "lib", "review", "scan", "law_registry_audit") unless
              defined?(Master::Review::Scan::LawRegistryAudit)
            Master::Review::Scan::LawRegistryAudit.new(root: Master::ROOT).call.assert_reconciled!
          end

          # Every catalogued Law is in the population, advisory ones too: the
          # catalogue calls them universal and the semantic reviewer asks them.
          # A lexical stream the Law's mode does not own is NOT_APPLICABLE; an
          # owned one no detector the scanner runs can measure is unmeasurable,
          # INCONCLUSIVE by construction, and keeps DONE out of reach.
          def assessment_canonical_law_info(info)
            Array(::Law.definitions.values).each do |law|
              assessment_add_canonical_law_row(info, law)
            end
          end

          def assessment_add_canonical_law_row(info, law)
            id = assessment_law_id(law)
            return if id.empty?

            measurable = law.scannable? && law.enforceable?
            info[id] = assessment_canonical_law_row(id, law, measurable)
          end

          def assessment_canonical_law_row(id, law, measurable)
            {
              id:,
              source_kind: :canonical,
              law:,
              scanner_law: nil,
              yaml_entry: nil,
              streams: FourStreamAssessment::STREAMS,
              surfaces: Array(law.assessment_surfaces).map(&:to_sym).uniq.freeze,
              unmeasurable_reason: nil,
              **assessment_lexical_ownership(law.mode, measurable:),
            }
          end

          def assessment_scanner_law_info(info)
            scanner_laws = @scanner.respond_to?(:laws) ? Array(@scanner.laws) : []
            scanner_laws.each do |law|
              assessment_add_scanner_law_row(info, law)
            end
          end

          def assessment_add_scanner_law_row(info, law)
            id = assessment_law_id(law)
            return if id.empty?
            return if assessment_existing_law_id(info, id)

            class_name = law.class.name.to_s
            semantic = class_name.match?(/AdversarialLaw|CommentDriftLaw|SemanticLaw/) ||
              (law.respond_to?(:set_agent) && !law.respond_to?(:check_ast))
            mode = law.mode.to_sym
            measurable = !(semantic || mode == :semantic)
            info[id] = assessment_scanner_law_row(id, law, mode, measurable)
          end

          def assessment_scanner_law_row(id, law, mode, measurable)
            {
              id:,
              source_kind: :scanner,
              law: nil,
              scanner_law: law,
              yaml_entry: nil,
              streams: FourStreamAssessment::STREAMS,
              surfaces: ::Law::ASSESSMENT_SURFACES,
              unmeasurable_reason: nil,
              **assessment_lexical_ownership(mode, measurable:),
            }
          end

          def assessment_add_opportunity_law(info, plan)
            opportunity_applicable = @opportunity_pass&.applicable?(plan.target) == true
            return opportunity_applicable unless opportunity_applicable
            return opportunity_applicable if assessment_existing_law_id(info, OpportunityPass::LAW_ID)

            info[OpportunityPass::LAW_ID] = {
              id: OpportunityPass::LAW_ID,
              source_kind: :opportunity,
              law: nil,
              scanner_law: nil,
              yaml_entry: nil,
              streams: [:lexical_opportunities].freeze,
              # The aggregate opportunity engine has no per-surface clean receipt.
              # Keep one source-level cell and leave its negative result inconclusive.
              surfaces: [:whole_file].freeze,
              unmeasurable_reason: nil,
            }
            opportunity_applicable
          end

          def assessment_add_visual_law(info, plan)
            visual_applicable = @visual_pass&.applicable?(plan.target) == true
            return visual_applicable unless visual_applicable
            return visual_applicable if assessment_existing_law_id(info, VisualPass::LAW_ID)

            info[VisualPass::LAW_ID] = {
              id: VisualPass::LAW_ID,
              source_kind: :visual,
              law: nil,
              scanner_law: nil,
              yaml_entry: nil,
              streams: [:visual].freeze,
              surfaces: %i[rendered_ui interactive_behavior].freeze,
              unmeasurable_reason: nil,
            }
            visual_applicable
          end

          def assessment_activate_matrix(info, files, plan, opportunity_applicable, visual_applicable)
            if info.empty?
              stage_failures[:assessment_matrix] << "no canonical or scanner-only Law identities; matrix not measured"
              return self
            end

            @assessment_law_info = info.freeze
            @assessment_ledger = FourStreamAssessment.new(
              laws: info.keys,
              clean_passes: [Integer(@clean_runs_required), 2].max,
              surfaces: FourStreamAssessment::SURFACES,
            )
            @assessment_plan = plan
            @assessment_surface_presence = nil
            @assessment_scope = Array(files).map { |path| File.expand_path(path) }.uniq.sort.freeze
            assessment_publish_matrix_started(info, plan, opportunity_applicable, visual_applicable)
            self
          end

          def assessment_publish_matrix_started(info, plan, opportunity_applicable, visual_applicable)
            @bus&.publish(
              "fix_loop:assessment_matrix_started",
              law_population: info.size,
              canonical_laws: info.values.count { |row| row[:source_kind] == :canonical },
              scanner_only_laws: info.values.count { |row| row[:source_kind] == :scanner },
              yaml_declarative_laws: info.values.count { |row| row[:source_kind] == :yaml_declarative },
              synthetic_opportunity: opportunity_applicable,
              synthetic_visual: visual_applicable,
              surfaces: FourStreamAssessment::SURFACES.size,
              expected_cells: info.size * FourStreamAssessment::STREAMS.size * FourStreamAssessment::SURFACES.size,
              plan_digest: plan.digest,
              status: "incomplete_until_every_applicable_cell_is_proved",
            )
          end

          def assessment_reset_plan_scope!(plan)
            @assessment_surface_presence = nil
            @assessment_surface_report = nil
            @assessment_surface_receipts = {}
            @assessment_surface_cache = {}
            @assessment_scope = plan.sources.map { |source| File.expand_path(source.path, plan.root) }.sort.freeze
            @assessment_file_coverage = nil
          end

          def assessment_publish_generation(plan)
            @bus&.publish(
              "fix_loop:assessment_generation",
              generation: @assessment_ledger.generation,
              iteration: @assessment_last_pass,
              plan_digest: plan.digest,
              source_digest: plan.source_digest,
            )
          end

          def assessment_plan_digest_fields
            {
              target: @assessment_plan&.target,
              plan_digest: @assessment_plan&.digest,
              source_digest: @assessment_plan&.source_digest,
              law_digest: @assessment_plan&.law_digest,
              identity_digest: @assessment_plan&.identity_digest,
              scope_digest: @assessment_plan&.scope_digest,
              law_source_digest: @assessment_plan&.law_source_digest,
              authority_digest: @assessment_plan&.authority_digest,
              toolchain_digest: @assessment_plan&.toolchain_digest,
              exclusion_digest: @assessment_plan&.exclusion_digest,
              adapter_digest: @assessment_plan&.adapter_digest,
            }
          end

          def assessment_unmeasured_artifact
            {
              schema_version: 3,
              status: "not_measured",
              reason: "no scanner-backed Law population was available",
              **assessment_plan_digest_fields,
              file_coverage: assessment_file_coverage_summary,
              quality_contract: assessment_quality_contract,
            }
          end

          def assessment_artifact_failure(error)
            {
              schema_version: 3,
              status: "incomplete",
              reason: "matrix artifact failed: #{error.class}: #{error.message.to_s[0, 150]}",
            }
          end

          # This is scanner-path coverage, not a clean-Law verdict. The Law × stream ×
          # surface matrix remains the authority for compliance; this docket names
          # every eligible path and makes an unvisited path visible.
          def assessment_file_coverage(observation, pass)
            findings_by_file = assessment_findings_by_file(observation)
            root = File.expand_path(@assessment_plan&.root || @root)
            files = Array(observation[:files]).sort.map { |path| assessment_file_row(observation, path, findings_by_file, root) }
            scanned = files.count { |row| row[:status] == "scanned" }

            {
              scope: "scanner_observation_only",
              pass: Integer(pass),
              status: files.empty? ? "not_measured" : (scanned == files.size ? "complete" : "incomplete"),
              expected: files.size,
              scanned:,
              unmeasured: files.size - scanned,
              files:,
            }
          end

          def assessment_findings_by_file(observation)
            findings_by_file = Hash.new { |hash, key| hash[key] = [] }
            observation.fetch(:findings, {}).each_value do |rows|
              Array(rows).each { |row| findings_by_file[row["file"]] << row }
            end
            Array(observation[:unclassified_findings]).each do |row|
              findings_by_file[row["file"]] << row
            end
            findings_by_file
          end

          def assessment_file_row(observation, path, findings_by_file, root)
            state = observation.fetch(:path_states, {})[path]
            file_findings = findings_by_file[path]
            scanned = state && state[:state] == :scanned
            row = {
              file: path.delete_prefix("#{root}/"),
              status: scanned ? "scanned" : "unmeasured",
              finding_count: observation.fetch(:finding_counts, {}).fetch(path, file_findings.size),
              laws: file_findings.map { |finding| finding["law"] }.compact.uniq.sort,
            }
            unless scanned
              row[:disposition] = state ? state[:state].to_s : "not_reached"
              row[:reason] = state ? state[:reason] : "scanner did not reach this eligible path before the pass ended"
            end
            row
          end

          def assessment_file_coverage_summary
            report = @assessment_file_coverage
            return { status: "not_measured", scope: "scanner_observation_only", expected: 0, scanned: 0, unmeasured: 0 } unless report

            report.slice(:status, :scope, :pass, :expected, :scanned, :unmeasured)
          end

          def surface_coverage_summary
            report = @assessment_surface_report
            return { status: "not_measured", reason: "surface adapters have not run" } unless report.is_a?(Hash)

            surfaces = report["surfaces"].is_a?(Hash) ? report["surfaces"] : {}
            {
              status: report["complete"] == true ? "complete" : "incomplete",
              digest: report["digest"],
              measured: surfaces.count { |_name, row| %w[assessed_clean not_applicable].include?(row["status"].to_s) },
              expected: surfaces.size,
              blockers: surfaces.filter_map do |name, row|
                next if %w[assessed_clean not_applicable].include?(row["status"].to_s)

                { surface: name, status: row["status"], reason: row["reason"].to_s[0, 180] }
              end.first(8),
            }
          end

          def surface_probe_candidate_clean?(observation:, signatures_stable:, semantic_gaps:, pending:, visual:, opportunities:)
            return false unless signatures_stable
            return false unless observation[:unclassified_findings].empty?
            return false unless observation[:findings].values.all?(&:empty?)
            return false unless semantic_gaps.empty? && pending.empty?
            return false unless @scan_phase&.semantic_full?

            visual_applicable = @visual_pass&.applicable?(@assessment_plan.target) == true
            opportunity_applicable = @opportunity_pass&.applicable?(@assessment_plan.target) == true
            return false unless surface_stage_clean?(visual, applicable: visual_applicable)
            return false unless surface_stage_clean?(opportunities, applicable: opportunity_applicable)

            true
          rescue StandardError
            false
          end

          def surface_stage_clean?(result, applicable:)
            return true unless applicable
            return false unless result&.ok?

            value = result.value!
            value.is_a?(Hash) && Array(value[:findings] || value["findings"]).empty?
          rescue StandardError
            false
          end

          def begin_assessment_pass(pass, files)
            return unless @assessment_ledger

            paths = Array(files).map { |path| File.expand_path(path) }.uniq.sort
            signatures = paths.to_h { |path| [path, assessment_signature(path)] }
            planned = @assessment_plan.source_signatures.to_h do |relative, signature|
              [File.expand_path(relative, @assessment_plan.root), signature]
            end
            stale_plan_paths = paths.select { |path| planned[path] != signatures[path] }
            @assessment_mutex.synchronize do
              @assessment_file_coverage = nil
              @assessment_observation = assessment_new_observation(pass, paths, signatures, stale_plan_paths)
            end
          end

          def assessment_new_observation(pass, paths, signatures, stale_plan_paths)
            {
              pass: Integer(pass),
              files: paths,
              signatures:,
              stale_plan_paths: stale_plan_paths.freeze,
              scanned: Set.new,
              path_states: {},
              refused: {},
              findings: Hash.new { |hash, key| hash[key] = [] },
              unclassified_findings: [],
            }
          end

          def assessment_signature(path)
            return unless File.file?(path) && !File.symlink?(path)

            stat = File.stat(path)
            [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
          rescue StandardError
            nil
          end

          def note_assessment_path(path, state, reason: nil, findings: [])
            absolute = File.expand_path(path)
            @assessment_mutex.synchronize do
              observation = @assessment_observation
              return unless observation && observation[:files].include?(absolute)

              observation[:path_states] ||= {}
              observation[:finding_counts] ||= Hash.new(0)
              assessment_note_path_state(observation, absolute, state, reason:, findings:)
            end
          rescue StandardError => e
            @bus&.publish("fix_loop:assessment_path_error", file: path.to_s, error: e.message)
          end

          def assessment_note_path_state(observation, absolute, state, reason:, findings:)
            case state
            when :scanned
              assessment_note_scanned_path(observation, absolute, findings)
            when :preflight, :failed
              observation[:refused][absolute] = reason.to_s[0, 200]
              observation[:path_states][absolute] = { state:, reason: reason.to_s[0, 200] }
            end
          end

          def assessment_note_scanned_path(observation, absolute, findings)
            observation[:scanned] << absolute
            observation[:path_states][absolute] = { state: :scanned, reason: nil }
            observation[:finding_counts][absolute] += Array(findings).size
            Array(findings).each { |finding| assessment_note_finding(observation, absolute, finding) }
          end

          def assessment_note_finding(observation, absolute, finding)
            row = finding.respond_to?(:to_h) ? finding.to_h.transform_keys(&:to_sym) : {}
            raw_id = (row[:law] || row[:law_id] || row[:rule]).to_s.strip
            return assessment_note_unclassified(observation, absolute, "[missing]", "finding has no Law identity") if raw_id.empty?

            law_id = assessment_existing_law_id(@assessment_law_info || {}, raw_id)
            return assessment_note_unclassified(observation, absolute, raw_id, "finding identity is absent from the runtime assessment population") unless law_id

            info = @assessment_law_info.fetch(law_id)
            stream = assessment_finding_stream(row, info)
            return assessment_note_unclassified(observation, absolute, law_id, "finding stream could not be resolved from explicit tags") unless stream && info[:streams].include?(stream)

            assessment_record_finding_row(observation, absolute, law_id, stream, row)
          end

          def assessment_note_unclassified(observation, absolute, law, reason)
            observation[:unclassified_findings] << {
              "law" => law, "file" => absolute,
              "reason" => reason
            }
          end

          def assessment_finding_stream(row, info)
            tags = Array(row[:tags]).map(&:to_s)
            stream_tag = tags.find { |tag| FourStreamAssessment::STREAMS.map(&:to_s).include?(tag) }
            stream = stream_tag&.to_sym
            return stream unless stream.nil?

            if tags.include?("opportunity") && info[:streams].include?(:semantic_opportunities)
              :semantic_opportunities
            elsif tags.include?("violation") && info[:streams].include?(:semantic_violations)
              :semantic_violations
            elsif info[:streams].one?
              info[:streams].first
            elsif info[:source_kind] == :scanner && info[:unmeasurable_streams].empty?
              LEXICAL_STREAM_FOR_MODE.fetch(info[:mode], :lexical_violations)
            end
          end

          def assessment_record_finding_row(observation, absolute, law_id, stream, row)
            observation[:findings][[law_id, stream]] << {
              "file" => absolute,
              "law" => law_id,
              "line" => row[:line].to_i,
              "message" => row[:message].to_s[0, 180],
            }
          end

          def finalize_assessment_pass(pass, visual:, opportunities:)
            observation = assessment_take_observation
            return unless observation && @assessment_ledger

            @assessment_file_coverage = assessment_file_coverage(observation, pass)
            signatures_stable = assessment_signatures_stable?(observation)
            semantic_gaps = @scanner.respond_to?(:semantic_gaps) ? @scanner.semantic_gaps : {}
            pending = semantic_pending
            plan_digest = @assessment_plan&.source_digest.to_s
            evidence = assessment_pass_evidence(pass, observation, plan_digest)
            assessment_report_unclassified(pass, observation[:unclassified_findings])
            candidate_clean = surface_probe_candidate_clean?(observation:, signatures_stable:, semantic_gaps:, pending:, visual:, opportunities:)
            assessment_capture_surface_report(observation, visual, candidate_clean)
            assessment_record_matrix_cells(pass, observation, signatures_stable:, semantic_gaps:, pending:, evidence:, visual:, opportunities:)
            @assessment_last_pass = Integer(pass)
            assessment_publish_matrix_pass(pass, plan_digest)
          rescue StandardError => e
            assessment_report_pass_failure(pass, e)
          end

          def assessment_take_observation
            @assessment_mutex.synchronize do
              current = @assessment_observation
              @assessment_observation = nil
              current
            end
          end

          def assessment_signatures_stable?(observation)
            observation[:files].all? do |path|
              observation[:signatures][path] == assessment_signature(path)
            end
          end

          def assessment_pass_evidence(pass, observation, plan_digest)
            [
              "plan_source_sha256=#{plan_digest}",
              "scanner=Master::Fix::Scanner#scan",
              "pass=#{pass}",
              "eligible_files=#{observation[:files].size}",
            ].freeze
          end

          def assessment_report_unclassified(pass, unclassified)
            return if unclassified.empty?

            stage_failures[:assessment_matrix] << "#{unclassified.size} unclassified finding(s): #{unclassified.first(2).map { |row| "#{row["law"]}@#{row["file"]}" }.join(", ")}"
            @bus&.publish("fix_loop:assessment_unclassified_findings", pass:, findings: unclassified.first(20))
          end

          def assessment_capture_surface_report(observation, visual, candidate_clean)
            @assessment_surface_report = SurfaceEvidence.capture(
              root: @assessment_plan.root,
              target: @assessment_plan.target,
              plan: @assessment_plan,
              files: observation[:files],
              visual_result: visual,
              reference_graph: @reference_graph,
              cache: (@assessment_surface_cache ||= {}),
              run_expensive: candidate_clean,
            )
            @assessment_surface_receipts = @assessment_surface_report.fetch("details", {})
            assessment_publish_surface_coverage
          end

          def assessment_publish_surface_coverage
            @bus&.publish(
              "fix_loop:surface_coverage",
              target: @assessment_plan.target,
              complete: @assessment_surface_report["complete"] == true,
              digest: @assessment_surface_report["digest"],
              surfaces: @assessment_surface_report.fetch("surfaces", {}).transform_values { |row| row["status"] },
            )
          end

          def assessment_record_matrix_cells(pass, observation, signatures_stable:, semantic_gaps:, pending:, evidence:, visual:, opportunities:)
            @assessment_law_info.each do |law_id, info|
              FourStreamAssessment::STREAMS.each do |stream|
                FourStreamAssessment::SURFACES.each do |surface|
                  result = assessment_cell_result(
                    law_id:, info:, stream:, surface:, pass:, observation:,
                    signatures_stable:, semantic_gaps:, pending:, evidence:,
                    visual:, opportunities:
                  )
                  record_assessment(law_id, stream, surface, pass, result)
                end
              end
            end
          end

          def assessment_publish_matrix_pass(pass, plan_digest)
            @bus&.publish(
              "fix_loop:assessment_matrix_pass",
              **@assessment_ledger.summary.merge(pass:, plan_source_digest: plan_digest),
            )
          end

          def assessment_report_pass_failure(pass, error)
            stage_failures[:assessment_matrix] << "pass #{pass}: #{error.class}: #{error.message.to_s[0, 180]}"
            @bus&.publish(
              "fix_loop:assessment_matrix_pass_failed",
              pass:, error_class: error.class.name, message: error.message,
            )
          end

          def valid_rendered_ui_receipt?(receipt)
            return false unless receipt.is_a?(Hash)
            return false unless (receipt["status"] || receipt[:status]).to_s == "assessed_clean"

            receipt_evidence = receipt["evidence"] || receipt[:evidence]
            captures = receipt_evidence.is_a?(Hash) ?
              Array(receipt_evidence["surfaces"] || receipt_evidence[:surfaces]) : []
            return false if captures.empty?

            validator = SurfaceEvidence.allocate
            captures.all? { |capture| validator.send(:valid_rendered_capture?, capture) }
          rescue StandardError
            false
          end

          def assessment_cell_result(law_id:, info:, stream:, surface:, pass:, observation:,
                                     signatures_stable:, semantic_gaps:, pending:, evidence:,
                                     visual:, opportunities:)
            declared_surfaces = Array(info[:surfaces]).map(&:to_sym)
            return assessment_result(:not_applicable, reason: "Law does not declare the #{surface} surface") unless declared_surfaces.include?(surface)

            owned = assessment_stream_ownership(law_id:, info:, stream:, evidence:)
            return owned if owned

            per_law_visual = assessment_visual_cell(law_id:, info:, stream:, surface:, evidence:)
            return per_law_visual if per_law_visual

            rendered_law = assessment_rendered_law_cell(law_id:, info:, stream:, surface:, visual:, evidence:)
            return rendered_law if rendered_law

            assessment_remaining_cell_result(law_id:, info:, stream:, surface:, pass:, observation:,
              signatures_stable:, semantic_gaps:, pending:, evidence:, visual:, opportunities:)
          end

          def assessment_remaining_cell_result(law_id:, info:, stream:, surface:, pass:, observation:,
                                               signatures_stable:, semantic_gaps:, pending:, evidence:,
                                               visual:, opportunities:)
            surface_evidence, surface_result = assessment_target_surface_result(law_id:, info:, surface:, evidence:)
            return surface_result if surface_result

            source_result = assessment_source_kind_cell_result(
              law_id:, info:, stream:, surface:, signatures_stable:, evidence:, surface_evidence:,
              visual:, opportunities:
            )
            return source_result if source_result

            assessment_file_cell_result(
              law_id:, info:, stream:, surface:, observation:, signatures_stable:,
              semantic_gaps:, pending:, evidence:, surface_evidence:
            )
          end

          def assessment_rendered_law_cell(law_id:, info:, stream:, surface:, visual:, evidence:)
            special_law = info[:source_kind] != :visual && law_id.to_s.casecmp?(VisualPass::LAW_ID)
            return unless special_law && stream == :visual && surface == :rendered_ui
            return assessment_result(:inconclusive, reason: "rendered visual review returned no result", evidence:) unless visual
            return assessment_result(:inconclusive, reason: visual.message.to_s, evidence:) if visual.err?

            rendered_receipt = (@assessment_surface_receipts || {})["rendered_ui"]
            receipt_problem = assessment_rendered_ui_receipt_problem(rendered_receipt)
            return assessment_result(:inconclusive, reason: receipt_problem, evidence:) if receipt_problem

            visual_value = visual.value!
            assessment_rendered_law_result(visual_value, law_id, rendered_receipt, evidence)
          end

          def assessment_rendered_law_result(visual_value, law_id, receipt, evidence)
            unless visual_value.is_a?(Hash) && (visual_value.key?(:findings) || visual_value.key?("findings"))
              return assessment_result(:inconclusive,
                reason: "rendered visual review did not return a law-findings collection", evidence:)
            end

            visual_rows = assessment_findings_for_law(visual_value[:findings] || visual_value["findings"], law_id)
            visual_evidence = assessment_rendered_law_evidence(receipt, evidence)
            assessment_result(visual_rows.any? ? :violation_found : :assessed_clean,
              evidence: visual_evidence, findings: visual_rows)
          end

          def assessment_rendered_law_evidence(receipt, evidence)
            Array(evidence) + [{
              "surface_probe" => "rendered_ui",
              "status" => "assessed_clean",
              "evidence_sha256" => receipt["evidence_sha256"],
              "counts" => receipt["counts"],
            }]
          end

          def assessment_rendered_ui_receipt_problem(receipt)
            return if valid_rendered_ui_receipt?(receipt)

            reason = receipt.is_a?(Hash) ? receipt["reason"].to_s : "rendered UI receipt is missing"
            reason = "rendered UI receipt is absent, incomplete or lacks valid screenshot/geometry evidence" if reason.empty?
            reason
          end

          def assessment_findings_for_law(rows, law_id)
            Array(rows).select { |row| (row[:law] || row["law"]).to_s.casecmp?(law_id) }
          end

          def assessment_target_surface_result(law_id:, info:, surface:, evidence:)
            return [nil, nil] unless SurfaceEvidence::SURFACES.include?(surface.to_s)

            receipt = (@assessment_surface_receipts || {})[surface.to_s]
            unless receipt.is_a?(Hash)
              return [nil, assessment_result(:inconclusive, reason: "target-level #{surface} surface receipt is missing", evidence:)]
            end

            surface_evidence = assessment_surface_probe_evidence(surface, receipt)
            base_evidence = Array(evidence) + [surface_evidence]
            result = assessment_surface_probe_result(
              law_id:, info:, surface:, receipt:, status: surface_evidence["status"],
              reason: (receipt["reason"] || receipt[:reason]).to_s, evidence: base_evidence
            )
            [surface_evidence, result]
          end

          def assessment_surface_probe_evidence(surface, receipt)
            {
              "surface_probe" => surface.to_s,
              "status" => (receipt["status"] || receipt[:status]).to_s,
              "evidence_sha256" => receipt["evidence_sha256"] || receipt[:evidence_sha256],
              "counts" => receipt["counts"] || receipt[:counts],
              "plan_digest" => @assessment_plan&.digest,
              "source_digest" => @assessment_plan&.source_digest,
            }.compact
          end

          def assessment_surface_probe_result(law_id:, info:, surface:, receipt:, status:, reason:, evidence:)
            case status
            when "not_applicable"
              assessment_result(:not_applicable,
                reason: reason.empty? ? "target has no #{surface} surface" : reason, evidence:)
            when "inconclusive"
              assessment_result(:inconclusive,
                reason: reason.empty? ? "#{surface} probe was inconclusive" : reason,
                evidence:, findings: assessment_receipt_findings(receipt))
            when "violation_found"
              assessment_surface_violation_result(law_id, info, surface, receipt, reason, evidence)
            when "assessed_clean"
              nil
            else
              assessment_result(:inconclusive,
                reason: "#{surface} probe returned unknown status #{status.inspect}", evidence:)
            end
          end

          def assessment_receipt_findings(receipt)
            Array(receipt["findings"] || receipt[:findings])
          end

          def assessment_surface_violation_result(law_id, info, surface, receipt, reason, evidence)
            findings = assessment_receipt_findings(receipt)
            return assessment_result(:violation_found, reason:, evidence:, findings:) if info[:source_kind] == :visual

            assessment_result(:inconclusive,
              reason: "#{surface} probe found a target-level issue not attributed to Law #{law_id}: #{reason}",
              evidence:, findings:)
          end

          def assessment_source_kind_cell_result(law_id:, info:, stream:, surface:, signatures_stable:,
                                                 evidence:, surface_evidence:, visual:, opportunities:)
            case info[:source_kind]
            when :opportunity
              assessment_opportunity_cell(law_id:, opportunities:, evidence:)
            when :visual
              assessment_visual_source_cell(law_id:, surface:, signatures_stable:, evidence:, surface_evidence:, visual:)
            end
          end

          def assessment_opportunity_cell(law_id:, opportunities:, evidence:)
            return assessment_result(:inconclusive, reason: "opportunity assessor returned no result", evidence:) unless opportunities
            return assessment_result(:inconclusive, reason: opportunities.message.to_s, evidence:) if opportunities.err?

            values = opportunities.value!
            rows = assessment_findings_for_law(values[:findings] || values["findings"], law_id)
            receipt = values[:assessment_evidence] || values["assessment_evidence"]
            receipt_value = ->(key) { receipt.is_a?(Hash) ? (receipt[key.to_sym] || receipt[key.to_s]) : nil }
            cell_evidence = Array(evidence) + (receipt.is_a?(Hash) ? [receipt] : [])
            unless assessment_opportunity_receipt_bound?(receipt_value)
              reason = Array(receipt_value.call(:reasons)).map(&:to_s).reject(&:empty?).first
              reason ||= "opportunity assessment receipt is missing, unstable or not bound to the current FixPlan"
              return assessment_result(:inconclusive, reason:, evidence: cell_evidence, findings: rows)
            end

            assessment_result(rows.any? ? :opportunity_found : :assessed_clean,
              evidence: cell_evidence, findings: rows)
          end

          def assessment_opportunity_receipt_bound?(receipt_value)
            @assessment_plan &&
              receipt_value.call(:status).to_s == "complete" &&
              receipt_value.call(:plan_digest).to_s == @assessment_plan.digest.to_s &&
              receipt_value.call(:source_digest).to_s == @assessment_plan.source_digest.to_s &&
              receipt_value.call(:scope_digest).to_s == @assessment_plan.scope_digest.to_s &&
              receipt_value.call(:target).to_s == @assessment_plan.target.to_s &&
              receipt_value.call(:source_hashes_verified) == true &&
              receipt_value.call(:snapshot_sha256).to_s == receipt_value.call(:snapshot_after_sha256).to_s
          end

          def assessment_visual_source_cell(law_id:, surface:, signatures_stable:, evidence:, surface_evidence:, visual:)
            return assessment_result(:inconclusive, reason: "source generation changed during visual assessment", evidence:) unless signatures_stable
            return assessment_result(:inconclusive, reason: "rendered review returned no result", evidence:) unless visual
            return assessment_result(:inconclusive, reason: visual.message.to_s, evidence:) if visual.err?
            return assessment_result(:assessed_clean, evidence: Array(evidence) + [surface_evidence].compact) if surface == :interactive_behavior

            values = visual.value!
            rows = assessment_findings_for_law(values[:findings] || values["findings"], law_id)
            assessment_result(rows.any? ? :violation_found : :assessed_clean, evidence:, findings: rows)
          end

          def assessment_file_cell_result(law_id:, info:, stream:, surface:, observation:,
                                          signatures_stable:, semantic_gaps:, pending:, evidence:, surface_evidence:)
            scoped_files = assessment_scoped_cell_files(info, stream, surface, observation)
            return assessment_result(:not_applicable, reason: "no eligible file matches this Law/surface scope") if scoped_files.empty?
            unless assessment_surface_supported?(info, surface, stream:)
              return assessment_unmeasurable("#{surface} has no assessor for this Law/stream adapter", evidence)
            end

            cell_evidence = Array(evidence) + [surface_evidence].compact
            cell_evidence, receipt_result = assessment_file_surface_evidence(surface, scoped_files, cell_evidence)
            return receipt_result if receipt_result

            found = Array(observation[:findings][[law_id, stream]]).select { |row| scoped_files.include?(row["file"]) }
            assessment_result_for_scope(
              stream:, applicable: scoped_files, found:, observation:, signatures_stable:,
              semantic: %i[semantic_violations semantic_opportunities].include?(stream),
              semantic_gaps:, pending:, evidence: cell_evidence
            )
          end

          def assessment_scoped_cell_files(info, stream, surface, observation)
            observation[:files].select do |path|
              assessment_law_applies?(info, path, stream:) &&
                assessment_surface_applies?(info, surface, path, stream:)
            end
          end

          def assessment_file_surface_evidence(surface, scoped_files, evidence)
            case surface
            when :structured_data
              assessment_structured_file_evidence(scoped_files, evidence)
            when :syntax_tree
              assessment_syntax_tree_file_evidence(scoped_files, evidence)
            else
              [evidence, nil]
            end
          end

          def assessment_structured_file_evidence(scoped_files, evidence)
            parsed = scoped_files.map { |path| parse_structured_surface(path) }
            failure = parsed.find { |row| row[:status] != :assessed_clean }
            return [evidence, assessment_result(:inconclusive, reason: failure[:reason], evidence:)] if failure

            [evidence + parsed.flat_map { |row| row[:evidence] }, nil]
          end

          def assessment_syntax_tree_file_evidence(scoped_files, evidence)
            receipts = @scanner.respond_to?(:ast_assessments) ? @scanner.ast_assessments : {}
            source_hashes = @assessment_plan.source_hashes.to_h do |relative, sha|
              [File.expand_path(relative, @assessment_plan.root), sha]
            end
            missing, receipt_evidence = assessment_ast_receipt_rows(scoped_files, receipts, source_hashes)
            if missing.any?
              paths = missing.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")
              reason = "syntax tree receipt missing/stale for #{paths}"
              return [evidence, assessment_result(:inconclusive, reason:, evidence:)]
            end

            [evidence + receipt_evidence, nil]
          end

          def assessment_ast_receipt_rows(scoped_files, receipts, source_hashes)
            missing = []
            receipt_evidence = []
            scoped_files.each do |path|
              row = assessment_ast_receipt_row(path, receipts, source_hashes)
              row ? receipt_evidence << row : missing << path
            end
            [missing, receipt_evidence]
          end

          def assessment_ast_receipt_row(path, receipts, source_hashes)
            expanded = File.expand_path(path)
            receipt = receipts[expanded]
            expected = source_hashes[expanded]
            return unless receipt && receipt["status"] == "assessed" && expected && receipt["sha256"] == expected

            "prism_ast=#{File.basename(path)} sha256=#{receipt["sha256"]}"
          end

          VISUAL_SURFACES = %i[rendered_ui interactive_behavior].freeze

          # The visual stream reads rendered output. The rendered evaluator reports
          # its own RENDERED_VISUAL_REFINEMENT findings, not a verdict per Law, so
          # a Law's visual cell on a target with rendered UI is unmeasurable rather
          # than clean; on a source surface, or a target with no UI, it does not apply.
          def assessment_visual_cell(law_id:, info:, stream:, surface:, evidence:)
            return unless stream == :visual
            return if info[:source_kind] == :visual || law_id.to_s.casecmp?(VisualPass::LAW_ID)
            unless VISUAL_SURFACES.include?(surface)
              return assessment_result(:not_applicable, reason: "visual reads rendered output, not #{surface}")
            end
            unless assessment_target_has_rendered_ui?
              return assessment_result(:not_applicable, reason: "target has no rendered UI")
            end

            reason = "the rendered evaluator reports #{VisualPass::LAW_ID} findings, not a verdict on #{law_id}"
            assessment_unmeasurable(reason, evidence)
          end

          # A stream the Law's mode does not own does not apply to it; one it owns
          # that nothing can measure is unmeasurable. nil when the stream is live.
          def assessment_stream_ownership(law_id:, info:, stream:, evidence:)
            if Array(info[:unowned_streams]).include?(stream)
              reason = "Law #{law_id} detects in #{info[:mode]} mode; #{stream} is not its stream"
              evidence = ["law_catalogue #{law_id} mode=#{info[:mode]}"]
              return assessment_result(:not_applicable, reason:, evidence:)
            end
            return assessment_unmeasurable(info[:unmeasurable_reason], evidence) if info[:unmeasurable_reason]
            if Array(info[:unmeasurable_streams]).include?(stream)
              reason = "Law #{law_id} has no deterministic assessor for #{stream}; it cannot be marked clean"
              return assessment_unmeasurable(reason, evidence)
            end
            assessment_unmeasurable("Law has no #{stream} assessor", []) unless info[:streams].include?(stream)
          end

          def assessment_unmeasurable(reason, evidence)
            assessment_result(:inconclusive, reason:, evidence:).merge(unmeasurable: true)
          end

          def assessment_surface_supported?(info, surface, stream:)
            return true if SurfaceEvidence::SURFACES.include?(surface.to_s)

            semantic = %i[semantic_violations semantic_opportunities].include?(stream)
            assessment_source_surface_supported?(info, surface, semantic)
          end

          def assessment_source_surface_supported?(info, surface, semantic)
            case info[:source_kind]
            when :canonical
              assessment_canonical_surface_supported?(surface, semantic)
            when :scanner
              assessment_scanner_surface_supported?(info, surface, semantic)
            when :yaml_declarative
              %i[whole_file lines documentation structured_data].include?(surface)
            when :opportunity
              info[:surfaces].include?(surface)
            when :visual
              surface == :rendered_ui
            else
              false
            end
          end

          def assessment_canonical_surface_supported?(surface, semantic)
            return true if %i[whole_file lines documentation structured_data].include?(surface)
            return semantic if surface == :sections

            false
          end

          def assessment_scanner_surface_supported?(info, surface, semantic)
            return true if %i[whole_file documentation structured_data].include?(surface)
            return semantic || !info[:scanner_law]&.respond_to?(:check_ast) if surface == :lines
            return semantic if surface == :sections

            return surface == :syntax_tree && info[:scanner_law]&.respond_to?(:check_ast)
            false
          end

          def assessment_law_applies?(info, path, stream:)
            semantic = %i[semantic_violations semantic_opportunities].include?(stream)
            case info[:source_kind]
            when :canonical
              assessment_canonical_law_applies?(info, path, semantic)
            when :scanner
              assessment_scanner_law_applies?(info, path)
            when :yaml_declarative
              assessment_yaml_law_applies?(info, path)
            else
              true
            end
          rescue StandardError
            false
          end

          def assessment_canonical_law_applies?(info, path, semantic)
            law = info[:law]
            # SemanticLaw deliberately considers every active Law on every
            # artifact. Language/path restrictions belong to the deterministic
            # adapter and must not erase universal semantic evidence.
            semantic || law.applies?(path, Master.language_for(path)&.to_sym)
          end

          def assessment_scanner_law_applies?(info, path)
            law = info[:scanner_law]
            return true unless law.respond_to?(:applies_to?)

            languages = law.respond_to?(:languages) ? law.languages : nil
            law.applies_to?(path, languages)
          end

          def assessment_yaml_law_applies?(info, path)
            entry = info[:yaml_entry]
            relative = path.delete_prefix("#{@root}/")
            return false if entry[:path_match] && !relative.include?(entry[:path_match].to_s.delete("/"))

            languages = Array(entry[:languages]).map(&:to_s)
            languages.empty? || languages.include?(Master.language_for(path).to_s)
          end

          def assessment_surface_applies?(info, surface, path, stream:)
            extension = File.extname(path).downcase
            language = Master.language_for(path).to_s
            semantic = %i[semantic_violations semantic_opportunities].include?(stream)
            verdict = assessment_plan_surface_applies?(surface)
            return verdict unless verdict.nil?

            verdict = assessment_lexeme_surface_applies?(info, surface, extension, language, semantic)
            return verdict unless verdict.nil?

            assessment_inventory_surface_applies?(surface)
          end

          def assessment_plan_surface_applies?(surface)
            case surface
            when :repository_tree, :directories
              File.directory?(@assessment_plan.target)
            when :file_names, :paths
              !@assessment_plan.sources.empty?
            when :whole_file
              true
            when :cross_file
              @assessment_plan.sources.size > 1
            end
          end

          def assessment_lexeme_surface_applies?(info, surface, extension, language, semantic)
            case surface
            when :lines
              semantic || info[:source_kind] != :canonical || info[:law].scope.to_sym == :line
            when :sections
              semantic
            when :syntax_tree
              !language.empty? && !%w[markdown yaml json toml].include?(language)
            when :structured_data
              %w[.yml .yaml .json .toml].include?(extension) || %w[yaml json toml].include?(language)
            when :documentation
              %w[.md .markdown .rst .txt].include?(extension) || language == "markdown"
            end
          end

          def assessment_inventory_surface_applies?(surface)
            case surface
            when :media_assets
              assessment_target_has_assets?(%w[.png .jpg .jpeg .webp .gif .svg .pdf .wav .mp3 .m4a .flac .mp4 .mov .webm])
            when :compiled_assets
              assessment_target_has_compiled_assets?
            when :rendered_ui, :interactive_behavior
              assessment_target_has_rendered_ui?
            when :tests
              assessment_target_has_tests?
            when :runtime
              runtime_extensions = %w[.rb .rake .sh .zsh .js .jsx .ts .tsx .html .erb .css .scss]
              @assessment_plan.sources.any? { |source| runtime_extensions.include?(File.extname(source.path).downcase) }
            when :deployment
              assessment_target_has_deployment_surface?
            else
              false
            end
          end

          def assessment_target_has_assets?(extensions)
            key = [:asset_extensions, extensions.sort]
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[key] if @assessment_surface_presence.key?(key)

            target = @assessment_plan.target
            return @assessment_surface_presence[key] = false unless File.directory?(target)

            @assessment_surface_presence[key] = extensions.any? do |extension|
              Dir.glob(File.join(target, "**", "*#{extension}")).any? do |path|
                File.file?(path) && !File.symlink?(path)
              end
            end
          rescue StandardError => e
            @bus&.publish("fix_loop:assessment_surface_inventory_failed", surface: key&.first, error: e.message)
            @assessment_surface_presence[key] = true
          end

          def assessment_target_has_compiled_assets?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:compiled_assets] if @assessment_surface_presence.key?(:compiled_assets)

            paths = @assessment_plan.sources.map(&:path)
            @assessment_surface_presence[:compiled_assets] = paths.any? do |path|
              path.match?(%r{(?:public/assets|app/assets/builds|vendor/assets)/}) ||
                File.basename(path).match?(/\A(?:manifest(?:-[a-f0-9]+)?\.json|.+\.min\.(?:css|js))\z/i)
            end || assessment_target_has_assets?(%w[.map])
          rescue StandardError
            @assessment_surface_presence[:compiled_assets] = true
          end

          def assessment_target_has_rendered_ui?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:rendered_ui] if @assessment_surface_presence.key?(:rendered_ui)

            target = @assessment_plan.target
            front_end = @assessment_plan.sources.any? do |source|
              source.path.match?(%r{(?:app/views|views|templates|frontend|src)/}) &&
                %w[.erb .html .htm .css .scss .js .jsx .ts .tsx].include?(File.extname(source.path).downcase)
            end
            # Inventory UI independently of adapter availability. If a
            # target contains a frontend but has no visual adapter, its UI
            # cells are INCONCLUSIVE, not falsely NOT_APPLICABLE.
            @assessment_surface_presence[:rendered_ui] = front_end
          rescue StandardError
            @assessment_surface_presence[:rendered_ui] = true
          end

          def assessment_target_has_tests?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:tests] if @assessment_surface_presence.key?(:tests)

            @assessment_surface_presence[:tests] = @assessment_plan.sources.any? do |source|
              source.path.match?(%r{(?:\A|/)(?:test|tests|spec)(?:/|\z)}) ||
                File.basename(source.path).match?(/(?:_test|_spec)\.(?:rb|js|ts|jsx|tsx)\z/)
            end
          end

          def assessment_target_has_deployment_surface?
            @assessment_surface_presence ||= {}
            return @assessment_surface_presence[:deployment] if @assessment_surface_presence.key?(:deployment)

            target = @assessment_plan.target
            target_label = target == @assessment_plan.root ? "." : target.delete_prefix(@assessment_plan.root + File::SEPARATOR)
            paths = @assessment_plan.sources.map(&:path)
            @assessment_surface_presence[:deployment] =
              target_label == "." || target_label.start_with?("OPENBSD", "RAILS") ||
              paths.any? do |path|
                File.basename(path).match?(/\A(?:Procfile|Dockerfile|compose\.ya?ml|.*\.service|.*deploy.*)\z/i) ||
                  path.match?(%r{(?:deploy|deployment|helm|terraform|k8s)/})
              end
          rescue StandardError
            @assessment_surface_presence[:deployment] = true
          end

          def parse_structured_surface(path)
            extension = File.extname(path).downcase
            text = File.read(path, encoding: "UTF-8")
            sha256 = Digest::SHA256.hexdigest(text)
            parser = assessment_structured_parser_name(extension, text)
            return assessment_unparsed_surface(extension) if parser.nil?

            {
              status: :assessed_clean,
              evidence: ["structured_data=#{parser} sha256=#{sha256} path=#{path}"],
            }
          rescue StandardError => e
            {
              status: :inconclusive,
              reason: "structured-data parser failed for #{path}: #{e.class}: #{e.message.to_s[0, 160]}",
              evidence: [],
            }
          end

          def assessment_structured_parser_name(extension, text)
            case extension
            when ".json"
              require "json"
              JSON.parse(text)
              "JSON.parse"
            when ".yml", ".yaml"
              require "yaml"
              YAML.parse(text)
              "YAML.parse"
            end
          end

          def assessment_unparsed_surface(extension)
            {
              status: :inconclusive,
              reason: "no structured-data parser registered for #{extension.empty? ? "extensionless input" : extension}",
              evidence: [],
            }
          end

          def assessment_gap_paths(entries, applicable)
            keys = entries.respond_to?(:keys) ? entries.keys : Array(entries)
            scope = Array(applicable).map { |path| File.expand_path(path) }.to_set
            roots = assessment_gap_roots
            matched = Set.new
            unresolved = []

            keys.each do |key|
              path, raw = assessment_resolve_gap_path(key, scope, roots)
              path ? matched << path : unresolved << raw if raw
            end

            [matched.to_a, unresolved]
          end

          def assessment_resolve_gap_path(key, scope, roots)
            raw = key.to_s
            candidates = assessment_gap_candidates(raw, roots)
            path = candidates.find { |candidate| scope.include?(candidate) }
            return [path, nil] if path
            return [nil, raw] if assessment_gap_path_outside_roots?(candidates, roots)

            [nil, nil]
          end

          def assessment_gap_roots
            [
              @assessment_plan&.root,
              (Master::REPO_ROOT if defined?(Master::REPO_ROOT)),
              Master::ROOT,
              @root,
            ].compact.map { |path| File.expand_path(path) }.uniq
          end

          def assessment_gap_candidates(raw, roots)
            if Pathname.new(raw).absolute?
              [File.expand_path(raw)]
            else
              roots.map { |root| File.expand_path(raw, root) }
            end
          end

          def assessment_gap_path_outside_roots?(candidates, roots)
            candidates.none? do |candidate|
              roots.any? { |root| candidate == root || candidate.start_with?(root + File::SEPARATOR) }
            end
          end

          def assessment_result_for_scope(stream:, applicable:, found:, observation:, signatures_stable:,
                                          semantic:, semantic_gaps:, pending:, evidence:)
            return assessment_result(:inconclusive, reason: "source bytes changed during this scan pass", evidence:) unless signatures_stable

            result = assessment_stale_plan_result(applicable, observation, evidence)
            return result if result

            result = assessment_unread_result(applicable, observation, evidence)
            return result if result

            result = assessment_refused_result(applicable, observation, evidence)
            return result if result

            return assessment_found_result(stream, found, evidence) if found.any?
            return assessment_result(:assessed_clean, evidence:) unless semantic

            assessment_semantic_scope_result(applicable:, semantic_gaps:, pending:, evidence:)
          end

          def assessment_stale_plan_result(applicable, observation, evidence)
            stale_plan = applicable.select { |path| Array(observation[:stale_plan_paths]).include?(path) }
            return if stale_plan.empty?

            assessment_result(
              :inconclusive,
              reason: "source differs from pinned FixPlan generation: #{stale_plan.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
              evidence:,
            )
          end

          def assessment_unread_result(applicable, observation, evidence)
            unread = applicable.reject { |path| observation[:scanned].include?(path) }
            return if unread.empty?

            assessment_result(
              :inconclusive,
              reason: "scanner did not examine every applicable file: #{unread.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
              evidence:,
            )
          end

          def assessment_refused_result(applicable, observation, evidence)
            refused = applicable.select { |path| observation[:refused].key?(path) }
            return if refused.empty?

            assessment_result(
              :inconclusive,
              reason: "scan short-circuited for #{refused.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
              evidence:,
            )
          end

          def assessment_found_result(stream, found, evidence)
            status = %i[lexical_opportunities semantic_opportunities].include?(stream) ? :opportunity_found : :violation_found
            assessment_result(status, evidence:, findings: found)
          end

          def assessment_semantic_scope_result(applicable:, semantic_gaps:, pending:, evidence:)
            return assessment_result(:inconclusive, reason: "semantic coverage is sampled or budgeted", evidence:) unless @scan_phase.semantic_full?

            result = assessment_pending_reads_result(pending, applicable, evidence)
            return result if result

            result = assessment_gap_reads_result(semantic_gaps, applicable, evidence)
            return result if result

            assessment_result(:assessed_clean, evidence:)
          end

          def assessment_pending_reads_result(pending, applicable, evidence)
            pending_paths, pending_unknown = assessment_gap_paths(pending, applicable)
            return assessment_result(
              :inconclusive,
              reason: "semantic reads pending for #{pending_paths.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
              evidence:,
            ) if pending_paths.any?
            return assessment_result(
              :inconclusive, reason: "semantic gap paths could not be scoped: #{pending_unknown.first(4).join(", ")}", evidence:
            ) if pending_unknown.any?

            nil
          end

          def assessment_gap_reads_result(semantic_gaps, applicable, evidence)
            gap_paths, gap_unknown = assessment_gap_paths(semantic_gaps, applicable)
            return assessment_result(
              :inconclusive,
              reason: "semantic read inconclusive for #{gap_paths.first(4).map { |path| path.delete_prefix("#{@root}/") }.join(", ")}",
              evidence:,
            ) if gap_paths.any?
            return assessment_result(
              :inconclusive, reason: "semantic gap paths could not be scoped: #{gap_unknown.first(4).join(", ")}", evidence:
            ) if gap_unknown.any?

            nil
          end

          def assessment_result(status, reason: nil, evidence: [], findings: [])
            { status:, reason:, evidence: Array(evidence), findings: Array(findings) }
          end

          def record_assessment(law_id, stream, surface, pass, result)
            @assessment_mutex.synchronize do
              @assessment_unmeasurable ||= Set.new
              key = [law_id, stream, surface]
              result[:unmeasurable] ? @assessment_unmeasurable << key : @assessment_unmeasurable.delete(key)
              @assessment_ledger.record(
                law: law_id, stream:, surface:, status: result.fetch(:status),
                iteration: Integer(pass), generation: @assessment_ledger.generation,
                reason: result[:reason], evidence: result[:evidence], findings: result[:findings]
              )
            end
          end
        end
      end
    end
  end
end
