# frozen_string_literal: true

require "set"
require_relative "../../law/definition"
require_relative "four_stream_assessment/reporting"

module Master
  module Fix
    # Runs every Law through five independent assessment streams on each
    # declared surface: lexical and semantic violations and opportunities, and
    # visual, which reads rendered output. Missing assessors are INCONCLUSIVE,
    # never clean.
    #
    # This is deliberately adapter-driven: language parsers, path inventories,
    # cross-file analyzers, browser probes and model reviewers each keep their
    # own evidence contract while sharing one convergence and coverage ledger.
    #
    # The terminal renderings (#summary, #report, #evidence_report) live in
    # fix/four_stream_assessment/reporting.rb, which re-opens this class.
    class FourStreamAssessment
      STREAMS = %i[
        lexical_violations
        lexical_opportunities
        semantic_violations
        semantic_opportunities
        visual
      ].freeze

      SURFACES = ::Law::ASSESSMENT_SURFACES

      FINDING_STATES = %i[violation_found opportunity_found].freeze

      STATES = %i[
        assessed_clean violation_found opportunity_found not_applicable inconclusive
      ].freeze

      # Machine-readable expectations only. A declared contract is not runtime
      # proof; callers must supply assessors and emit evidence for each cell.
      def self.contract
        {
          version: 1,
          streams: STREAMS.map(&:to_s),
          surfaces: SURFACES.map(&:to_s),
          statuses: (STATES + [:pending]).map(&:to_s),
          clean_passes_required: 2,
          completion_rule: "all applicable law x stream x surface cells have two consecutive evidence-backed clean readings after the last mutation",
          runtime_status: "contract_only_not_measurement",
        }
      end

      Result = Data.define(
        :law, :stream, :surface, :status, :iteration, :generation,
        :reason, :evidence, :findings, :repair
      )

      attr_reader :laws, :surfaces, :history, :clean_passes, :max_iterations,
                  :generation, :last_mutation_iteration

      def initialize(laws:, surfaces: SURFACES, clean_passes: 2, max_iterations: 15)
        @laws = Array(laws).map { |law| law_id(law) }.uniq.freeze
        @surfaces = Array(surfaces).map(&:to_sym).uniq.freeze
        @clean_passes = Integer(clean_passes)
        @max_iterations = Integer(max_iterations)
        raise ArgumentError, "law population is empty" if @laws.empty?
        raise ArgumentError, "surface population is empty" if @surfaces.empty?
        raise ArgumentError, "clean_passes must be positive" unless @clean_passes.positive?
        raise ArgumentError, "max_iterations must be positive" unless @max_iterations.positive?
        unknown_surfaces = @surfaces - SURFACES
        raise ArgumentError, "unknown surfaces: #{unknown_surfaces.join(', ')}" unless unknown_surfaces.empty?

        @history = Hash.new { |hash, key| hash[key] = [] }
        @generation = 0
        @last_mutation_iteration = 0
      end

      # assessors may be keyed by [stream, surface] or by stream. Each assessor
      # returns { status:, reason:, evidence:, findings: }. The repairer receives
      # the same context and returns { changed: true }. Every global round visits
      # every cell. Any mutation advances the generation and invalidates prior
      # clean readings everywhere; DONE requires two mutation-free clean rounds.
      def run(assessors:, repairer: nil)
        1.upto(max_iterations) do |iteration|
          cells.each do |law, stream, surface|
            assess_cell(law:, stream:, surface:, iteration:, assessors:, repairer:)
          end
          break if clean?
        end

        finalize_open_cells
        report
      end

      def record(law:, stream:, surface:, status:, iteration:, generation: @generation,
                 reason: nil, evidence: [], findings: [], repair: nil)
        key = cell_key(law, stream, surface)
        state = validate_key!(key, status)
        detail = reason.to_s.strip
        validate_reason!(state, detail)
        evidence_rows = evidence.nil? ? [] : Array(evidence)
        finding_rows = findings.nil? ? [] : Array(findings)
        validate_evidence!(state, evidence_rows, finding_rows)
        iteration, generation = validate_progress!(key, iteration, generation)
        row = Result.new(
          law: key[0], stream: key[1], surface: key[2], status: state,
          iteration:, generation:, reason: detail.empty? ? nil : detail,
          evidence: evidence_rows.freeze, findings: finding_rows.freeze, repair:
        )
        history[key] << row
        row
      end

      # Called when the owning /fix plan detects a source, scope, Law, authority,
      # toolchain, exclusion or adapter mutation. Old clean readings remain auditable
      # but cannot satisfy the new generation's clean streak.
      def invalidate!(iteration:, reason:)
        iteration = Integer(iteration)
        raise ArgumentError, "mutation iteration cannot be negative" if iteration.negative?

        @generation += 1
        @last_mutation_iteration = [@last_mutation_iteration, iteration].max
        @invalidations ||= []
        @invalidations << {
          iteration:,
          generation: @generation,
          reason: reason.to_s[0, 240],
        }.freeze
        @generation
      end

      # A cell is complete only after the required consecutive clean readings or
      # a reasoned not-applicable decision. Any missing work remains open.
      def complete?
        cells.all? do |key|
          latest = history[key].last
          next false unless latest

          (latest.status == :not_applicable && latest.generation == generation) ||
            (latest.status == :assessed_clean && clean_streak(key) >= clean_passes)
        end
      end

      # Per stream, how many cells something can measure, how many no assessor
      # can (the caller names those: inconclusive by construction, so they keep
      # DONE out of reach), and how many do not apply.
      def coverage(unmeasurable: Set.new)
        STREAMS.to_h { |stream| [stream.to_s, stream_coverage(stream, unmeasurable)] }
      end

      def clean?
        complete? && cells.all? do |key|
          %i[assessed_clean not_applicable].include?(history[key].last.status)
        end
      end

      private

      def cells
        @cells ||= laws.product(STREAMS, surfaces).freeze
      end

      def cell_key(law, stream, surface)
        [law_id(law), stream.to_sym, surface.to_sym]
      end

      def law_id(law)
        value = law.respond_to?(:id) ? law.id : law
        id = value.to_s.strip
        raise ArgumentError, "law id is blank" if id.empty?

        id
      end

      # Cell and reading validity, in the order record() has always reported
      # problems, so callers see the same first ArgumentError for the same input.
      def validate_key!(key, status)
        raise ArgumentError, "unknown law: #{key[0]}" unless laws.include?(key[0])
        raise ArgumentError, "unknown stream: #{key[1]}" unless STREAMS.include?(key[1])
        raise ArgumentError, "unknown surface: #{key[2]}" unless surfaces.include?(key[2])

        state = status.to_sym
        raise ArgumentError, "unknown assessment state: #{state}" unless STATES.include?(state)

        state
      end

      def validate_reason!(state, detail)
        return unless %i[not_applicable inconclusive].include?(state) && detail.empty?

        raise ArgumentError, "#{state} requires a reason"
      end

      def validate_evidence!(state, evidence_rows, finding_rows)
        if state == :assessed_clean && evidence_rows.empty?
          raise ArgumentError, "assessed_clean requires evidence naming what was examined"
        end
        return unless FINDING_STATES.include?(state) && evidence_rows.empty? && finding_rows.empty?

        raise ArgumentError, "#{state} requires evidence or a finding"
      end

      def validate_progress!(key, iteration, generation)
        iteration = Integer(iteration)
        generation = Integer(generation)
        raise ArgumentError, "iteration must be positive" unless iteration.positive?
        raise ArgumentError, "generation cannot be negative" if generation.negative?
        previous = history[key].last
        return [iteration, generation] unless previous && iteration <= previous.iteration

        raise ArgumentError, "iteration must advance for #{key.join("/")}"
      end

      # Readings collected during a round that made a repair cannot count as
      # post-repair clean passes. Require two entire later rounds.
      def clean_streak(key)
        history[key].reverse.take_while do |row|
          row.status == :assessed_clean &&
            row.generation == generation &&
            row.iteration > last_mutation_iteration
        end.size
      end

      def assessor_for(assessors, stream, surface)
        assessors[[stream, surface]] || assessors[stream] || assessors[stream.to_s]
      end

      def assess_cell(law:, stream:, surface:, iteration:, assessors:, repairer:)
        key = [law, stream, surface]
        assessor = assessor_for(assessors, stream, surface)
        return missing_assessor(key, stream, surface, iteration) unless assessor.respond_to?(:call)

        outcome = normalize_outcome(assessor.call(
          law:, stream:, surface:, iteration:, prior: history[key].dup.freeze,
        ))
        return record_outcome(key, outcome, iteration) unless FINDING_STATES.include?(outcome[:status])

        repair_finding(key, outcome, iteration, repairer)
      rescue StandardError => e
        record(**record_args(key, :inconclusive, iteration,
          reason: "assessment/repair failed: #{e.class}: #{e.message}"))
        false
      end

      def missing_assessor(key, stream, surface, iteration)
        record(**record_args(key, :inconclusive, iteration,
          reason: "no assessor registered for #{stream}/#{surface}"))
        false
      end

      def record_outcome(key, outcome, iteration)
        record(**record_args(key, outcome.fetch(:status), iteration,
          reason: outcome[:reason], evidence: outcome[:evidence],
          findings: outcome[:findings]))
        false
      end

      def repair_finding(key, outcome, iteration, repairer)
        unless repairer.respond_to?(:call)
          record(**record_args(key, :inconclusive, iteration,
            reason: "finding remains; no repairer is registered",
            evidence: outcome[:evidence], findings: outcome[:findings]))
          return false
        end

        repair = repairer.call(
          law: key[0], stream: key[1], surface: key[2], status: outcome[:status],
          findings: Array(outcome[:findings]), evidence: Array(outcome[:evidence]), iteration:
        )
        changed = repair == true || (repair.respond_to?(:[]) && repair[:changed] == true)
        retryable = repair.respond_to?(:[]) && repair[:retryable] == true
        unless changed
          record(**record_args(key, :inconclusive, iteration,
            reason: unchanged_repair_reason(repair, retryable),
            evidence: outcome[:evidence], findings: outcome[:findings], repair:))
          return false
        end

        record_repair(key, outcome, iteration, repair)
      end

      def unchanged_repair_reason(repair, retryable)
        reason = repair.respond_to?(:[]) ? repair[:reason] : nil
        reason = "repair did not change the artifact" if reason.to_s.strip.empty? && !retryable
        reason = "repair requires another iteration" if reason.to_s.strip.empty?
        reason
      end

      def record_repair(key, outcome, iteration, repair)
        record(**record_args(key, outcome[:status], iteration,
          evidence: outcome[:evidence], findings: outcome[:findings], repair:))
        @generation += 1
        @last_mutation_iteration = iteration
        true
      end

      def finalize_open_cells
        cells.each do |key|
          latest = history[key].last
          next unless latest
          next if latest.status == :not_applicable || latest.status == :inconclusive
          next if latest.status == :assessed_clean &&
                  latest.generation == @generation && clean_streak(key) >= clean_passes

          record(**record_args(key, :inconclusive, max_iterations + 1,
            reason: "iteration limit reached before #{clean_passes} consecutive clean assessments (last state: #{latest.status})",
            generation: @generation, evidence: latest.evidence, findings: latest.findings))
        end
      end

      def normalize_outcome(value)
        raise ArgumentError, "assessor must return a Hash" unless value.is_a?(Hash)

        row = value.transform_keys(&:to_sym)
        row[:status] = row.fetch(:status).to_sym
        raise ArgumentError, "unknown assessment state: #{row[:status]}" unless STATES.include?(row[:status])

        if %i[not_applicable inconclusive].include?(row[:status]) && row[:reason].to_s.strip.empty?
          raise ArgumentError, "#{row[:status]} needs a reason"
        end
        if row[:status] == :assessed_clean && Array(row[:evidence]).compact.empty?
          raise ArgumentError, "assessed_clean needs evidence naming what was examined"
        end
        if FINDING_STATES.include?(row[:status]) &&
           Array(row[:evidence]).compact.empty? && Array(row[:findings]).compact.empty?
          raise ArgumentError, "#{row[:status]} needs evidence or a finding"
        end
        row
      end

      def stream_coverage(stream, unmeasurable)
        keys = cells.select { |key| key[1] == stream }
        states = keys.to_h { |key| [key, history[key].last&.status] }
        not_applicable = states.count { |_key, state| state == :not_applicable }
        blind = states.count { |key, state| state == :inconclusive && unmeasurable.include?(key) }

        { cells: keys.size, measurable: keys.size - not_applicable - blind, unmeasurable: blind, not_applicable: }
      end

      def record_args(key, status, iteration, **values)
        { law: key[0], stream: key[1], surface: key[2], status:, iteration:, **values }
      end
    end

    # Dimension-level read model over the canonical Law ledger. It does not
    # declare Laws or duplicate their authority; it groups the same measured
    # cells into engineering, editorial, visual, experience and operations.
    class QualityContract
      SPECIALISTS = {
        editorial: /BRINGHURST|STRUNK|PROSE|TYPOGRAPHY|READABILITY|GRAMMAR|CLARITY|EDITORIAL|COPY/,
        visual: /VISUAL|DESIGN|AESTHETIC|COMPOSITION|PROPORTION|WHITESPACE|GRID|COLOR|COLOUR|CONTRAST|ALIGNMENT|LAYOUT|TYPE_HIERARCHY/,
        experience: /ACCESS|ARIA|INTERACTION|USABILITY|UX|CONVERSATION|KEYBOARD|FOCUS|FORM|MOBILE|TOUCH|NAVIGATION|FEEDBACK|INPUT/,
        operations: /OPENBSD|DEPLOY|HOST|DAEMON|SERVICE|BACKUP|RESTORE|RELEASE|PORTABILITY|SHELL|UNIX|OPERAT/,
      }.freeze
      DIMENSIONS = %i[engineering editorial visual experience operations].freeze

      def self.build(ledger:, surface_report: nil, target: nil, files: [], lane: :code,
                     visual_groups: nil, improvement: nil, law_tags: {})
        new(ledger:, surface_report:, target:, files:, lane:, visual_groups:, improvement:, law_tags:).build
      end

      def initialize(ledger:, surface_report:, target:, files:, lane:, visual_groups:, improvement:, law_tags:)
        @ledger = ledger
        @surface_report = surface_report || {}
        @target = target.to_s.tr("\\", "/")
        @files = Array(files).map { |path| path.to_s.tr("\\", "/") }
        @lane = lane.to_s
        @visual_groups = visual_groups
        @improvement = improvement
        @law_tags = law_tags || {}
      end

      def build
        dimensions = DIMENSIONS.to_h { |name| [name, dimension(name)] }
        validation = external_validation
        workflows = workflow_receipts
        matrix = matrix_summary
        statuses = assessed_statuses(dimensions, validation, workflows)
        compliance = compliance_status(dimensions, workflows, matrix)
        {
          schema_version: 1, overall_status: overall_status(statuses, compliance),
          compliance_status: compliance, dimensions:, external_validation: validation,
          workflows:, matrix:,
          rule: "local compliance and external product proof are separate; missing evidence never passes",
        }
      rescue StandardError => e
        build_failure(e)
      end

      private

      def build_failure(error)
        {
          schema_version: 1, overall_status: "BLOCKED",
          reason: "quality contract could not be assembled: #{error.class}: #{error.message.to_s[0, 180]}",
          dimensions: {}, external_validation: {}, workflows: {},
        }
      end

      # Grouped visual repair is a local defect-removal gate. Continuous
      # improvement is deliberately separate: an open elevation opportunity
      # belongs in overall_status, not in the compliance verdict.
      def compliance_status(dimensions, workflows, matrix)
        local_statuses = dimension_statuses(dimensions) + compliance_workflows(workflows)
        return "BLOCKED" if @ledger.nil?
        return "FAIL" if local_statuses.include?("FAIL")
        return "BLOCKED" if local_statuses.include?("BLOCKED")
        return "INCONCLUSIVE" if matrix[:status] != "complete" ||
          local_statuses.any? { |status| %w[INCONCLUSIVE NOT_RUN].include?(status) }
        return "PASS" if local_statuses.all? { |status| status == "PASS" }

        "NOT_RUN"
      end

      def dimension_statuses(dimensions)
        dimensions.values.map { |row| row[:status] }
      end

      def compliance_workflows(workflows)
        [:grouped_visual_repair].filter_map do |name|
          row = workflows[name]
          row[:status] if row && row[:applicable]
        end
      end

      def assessed_statuses(dimensions, validation, workflows)
        assessed = dimensions.values + validation.values.select { |row| row[:applicable] } +
          workflows.values.select { |row| row[:applicable] }
        assessed.map { |row| row[:status] }.uniq
      end

      def overall_status(statuses, compliance)
        return "BLOCKED" if @ledger.nil?
        return "FAIL" if statuses.include?("FAIL")
        return "BLOCKED" if statuses.include?("BLOCKED")
        return "INCONCLUSIVE" if compliance != "PASS" ||
          statuses.any? { |status| %w[INCONCLUSIVE NOT_RUN].include?(status) }
        return "PASS" if statuses.include?("PASS")

        "NOT_RUN"
      end

      def read(hash, key, fallback = nil)
        return fallback unless hash.is_a?(Hash)

        hash.key?(key) ? hash[key] : hash.fetch(key.to_s, fallback)
      end

      def cells = Array(read(@ledger, :cells))

      def matrix_summary
        summary = read(@ledger, :summary, {})
        surface_complete = read(@surface_report, :complete)
        complete = read(summary, :complete) == true && surface_complete == true
        {
          status: complete ? "complete" : "incomplete",
          surface_evidence: surface_complete.nil? ? "NOT_RUN" : (surface_complete ? "PASS" : "INCONCLUSIVE"),
          laws: read(summary, :laws, 0).to_i,
          expected_cells: read(summary, :expected_cells, 0).to_i,
          recorded_cells: read(summary, :recorded_cells, 0).to_i,
          inconclusive_cells: read(summary, :inconclusive_cells, 0).to_i,
          clean_passes_required: read(summary, :clean_passes_required, 2).to_i,
        }
      end

      def dimension_for(law_id)
        tags = Array(@law_tags[law_id] || @law_tags[law_id.to_sym]).map { |tag| tag.to_s.upcase }
        return :editorial if tags.any? { |tag| %w[TYPOGRAPHY EDITORIAL PROSE WRITING].include?(tag) }
        return :visual if tags.any? { |tag| %w[VISUAL VISUAL_DESIGN AESTHETIC DESIGN LAYOUT COMPOSITION].include?(tag) }
        return :experience if tags.any? { |tag| %w[UX UX_LAWS ACCESSIBILITY INTERACTION USABILITY].include?(tag) }
        return :operations if tags.any? { |tag| %w[OPERATIONS OPENBSD DEPLOYMENT].include?(tag) }

        SPECIALISTS.each { |name, pattern| return name if law_id.match?(pattern) }
        :engineering
      end

      def dimension(name)
        rows = cells.select { |row| dimension_for(read(row, :law).to_s) == name }
        applicable = rows.reject { |row| read(row, :status).to_s == "not_applicable" }
        {
          status: dimension_status(applicable),
          applicable: !applicable.empty?,
          law_ids: rows.map { |row| read(row, :law).to_s }.uniq.sort,
          cells: rows.size, applicable_cells: applicable.size,
          failures: status_count(applicable, "violation_found"),
          open_opportunities: status_count(applicable, "opportunity_found"),
          inconclusive: inconclusive_count(applicable),
          not_applicable: rows.size - applicable.size,
          evidence: "FourStreamAssessment Law × stream × surface ledger",
        }
      end

      def status_count(rows, state)
        rows.count { |row| read(row, :status).to_s == state }
      end

      def inconclusive_count(rows)
        required = [read(read(@ledger, :summary, {}), :clean_passes_required, 2).to_i, 1].max
        rows.count do |row|
          state = read(row, :status).to_s
          state == "inconclusive" || state == "pending" ||
            (state == "assessed_clean" && read(row, :clean_streak, 0).to_i < required)
        end
      end

      def dimension_status(applicable)
        return "NOT_RUN" if applicable.empty?
        return "FAIL" if status_count(applicable, "violation_found").positive?
        return "INCONCLUSIVE" if status_count(applicable, "opportunity_found").positive? ||
          inconclusive_count(applicable).positive?
        return "PASS" if applicable.all? { |row| read(row, :status).to_s == "assessed_clean" }

        "INCONCLUSIVE"
      end

      def target_has?(tree)
        [@target, *@files].any? { |path| path.split("/").include?(tree) }
      end

      def surface_status(name)
        surfaces = read(@surface_report, :surfaces, {})
        row = read(surfaces, name, {})
        return "NOT_RUN" unless row.is_a?(Hash) && !row.empty?

        state = read(row, :status).to_s
        reason = read(row, :reason).to_s
        return "NOT_RUN" if state == "inconclusive" && reason.match?(/deferred|not run|not executed/i)

        case state
        when "assessed_clean" then "PASS"
        when "violation_found" then "FAIL"
        when "inconclusive" then "INCONCLUSIVE"
        when "not_applicable" then "NOT_RUN"
        else "INCONCLUSIVE"
        end
      end

      def local_surface(name)
        status = surface_status(name)
        { status:, applicable: status != "NOT_RUN", evidence: "SurfaceEvidence receipt: #{name}" }
      end

      def external_row(applicable, reason)
        {
          status: applicable ? "INCONCLUSIVE" : "NOT_RUN",
          applicable:,
          reason: applicable ? reason : "surface is not present in this target",
        }
      end

      def external_validation
        local_surfaces.merge(external_rows(external_presence)).merge(user_acceptance: user_acceptance_row)
      end

      def local_surfaces
        {
          local_test_suite: local_surface("tests"),
          local_runtime: local_surface("runtime"),
          local_deployment_manifest: local_surface("deployment"),
        }
      end

      # File signatures only raise the external question; they never answer it,
      # so a present target still owes the named human or rendered-output review.
      def external_presence
        rails = target_has?("RAILS")
        {
          documents: documents_present?,
          rails:,
          openbsd: target_has?("OPENBSD"),
          audio: audio_present?,
          visual_media: visual_media_present? && !rails,
          biz: target_has?("BIZ"),
        }
      end

      def documents_present?
        target_has?("BIZ") || @files.any? { |path| path.match?(/\.(?:pdf|docx|xlsx|pptx)\z/i) }
      end

      def audio_present?
        @files.any? { |path| path.match?(/\.(?:wav|mp3|m4a|aac|ogg|flac)\z/i) } ||
          @target.match?(%r{(?:\A|/)STUDIO/dilla(?:/|\z)})
      end

      def visual_media_present?
        @files.any? { |path| path.match?(/\.(?:png|jpe?g|gif|webp|avif|svg|mp4|mov|webm)\z/i) } ||
          @target.match?(%r{(?:\A|/)STUDIO/postpro(?:/|\z)})
      end

      def external_rows(presence)
        {
          document_rendering: external_row(presence[:documents],
            "format-aware source check and rendered-output comparison are not established by file signatures"),
          assistive_technology: external_row(presence[:rails],
            "browser and DOM checks do not prove screen-reader or real-device acceptance"),
          visual_media_review: external_row(presence[:visual_media],
            "asset signatures and source inspection do not prove composition, hierarchy or optical quality of rendered media"),
          live_openbsd_host: external_row(presence[:openbsd],
            "local manifests do not prove the live host, daemon or deployed service state"),
          human_listening: external_row(presence[:audio],
            "asset integrity and signal checks do not establish musical or listening quality"),
          business_and_legal_review: external_row(presence[:biz],
            "business assumptions, factual claims and legal effect require qualified human review"),
        }
      end

      def user_acceptance_row
        {
          status: "NOT_RUN", applicable: false,
          reason: "operator/user acceptance remains a human decision outside an automated repair run",
        }
      end

      def workflow_receipts
        { grouped_visual_repair: visual_workflow, continuous_improvement: improvement_workflow }
      end

      def visual_workflow
        unless target_has?("RAILS") && %w[all visual].include?(@lane)
          return { status: "NOT_RUN", applicable: false,
                   reason: "grouped visual repair is not scheduled for this target/lane" }
        end
        unless @visual_groups.is_a?(Hash)
          return { status: "INCONCLUSIVE", applicable: true,
                   reason: "grouped visual repair ran without a recorded outcome" }
        end

        findings = read(@visual_groups, :findings, 0).to_i
        remaining = read(@visual_groups, :remaining, findings).to_i
        {
          status: visual_status(findings, remaining),
          applicable: true, findings:,
          groups: read(@visual_groups, :groups, 0).to_i,
          cleared: read(@visual_groups, :cleared, 0).to_i,
          remaining:, resweep: read(@visual_groups, :resweep) == true,
          report: read(@visual_groups, :report),
        }
      end

      def visual_status(findings, remaining)
        resweep = read(@visual_groups, :resweep) == true
        cleared = read(@visual_groups, :cleared, 0).to_i
        groups = read(@visual_groups, :groups, 0).to_i
        if findings.zero? || (resweep && remaining.zero? && cleared == groups)
          "PASS"
        elsif resweep && remaining.positive?
          "FAIL"
        else
          "INCONCLUSIVE"
        end
      end

      def improvement_workflow
        unless %w[all elevate].include?(@lane)
          return { status: "NOT_RUN", applicable: false, reason: "improvement lane not selected" }
        end
        return no_assessment_workflow if !@improvement.is_a?(Hash) ||
          read(@improvement, :evaluated_passes, 0).to_i.zero?
        return unmeasured_workflow if read(@improvement, :measured_files, 0).to_i.zero?

        # Findings are the latest post-repair assessment, not a cumulative count
        # of opportunities repeated across passes. Only a clean re-observation
        # proves this workflow complete.
        findings = read(@improvement, :findings, 0).to_i
        status = findings.zero? ? "PASS" : "INCONCLUSIVE"
        @improvement.merge(status:, applicable: true)
      end

      def no_assessment_workflow
        { status: "INCONCLUSIVE", applicable: true, reason: "improvement engine recorded no assessment" }
      end

      def unmeasured_workflow
        {
          status: "INCONCLUSIVE", applicable: true,
          reason: "no supported improvement domain was measured; file presence is not proof",
          files_seen: read(@improvement, :files_seen, 0).to_i,
          measured_files: 0,
          domains: [],
        }
      end
    end
  end
end
