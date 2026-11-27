# frozen_string_literal: true

require_relative "tribunal"
require_relative "../../fix/best_of_n"
require_relative "../../fix/taste_memory"

module Master
  module Review
    module Council
      # Evidence, specialist panel, reciprocal critique, and final arbitration.
      class Critique
        MODES = Modes::TABLE

        def initialize(budget: nil, mode:, agent:, event_bus: nil, audio_path: nil, files: nil, visual_image: nil, visual_images: nil, visual_context: nil, briefing: nil, speak_personas: false, explore: true, harvest: true)
          @mode = MODES.fetch(mode) { raise ArgumentError, "unknown critique mode: #{mode}" }
          @agent = agent
          @bus = event_bus
          @audio_path = audio_path
          @files_override = files
          @visual_image = with_extra_images(visual_image, visual_images)
          @visual_context = visual_context
          @briefing = briefing.to_s.strip
          @speak_personas = speak_personas
          @budget = budget
          @candidate_limit = Master::Fix::UserSimulation.candidate_count if explore
          @harvest = harvest
        end

        # One council is one wall-clock budget (PassClock): a panel that has not
        # finished by then has said what it will say.
        def run = Master::Review::LLMDispatcher::PassClock.within(@budget) { run_panel }

        def run_panel
          preset = load_preset
          panel = build_panel(preset)
          payload = build_payload(preset)
          @bus&.publish(@mode[:start_event], files: payload[:files], personas: panel.map(&:name))

          result = deliberate(panel, payload)
          return result unless result.ok?

          build_run_result(payload, result.value!)
        end

        private

        def build_run_result(payload, feedback)
          return inconclusive_run_result(payload, feedback) if feedback_inconclusive?(feedback)

          issues = panel_issue_entries(feedback)
          judge = Array(feedback).find { |entry| entry[:persona] == "Judge" }
          return Master::Result.err("critique: final judge missing", category: :inconclusive) unless judge

          candidates = Array(judge[:candidates])
          selected = Array(judge[:structured_findings]).select { |finding| CherryPick.proposed?(finding) }
          reason = selection_error(candidates, selected, judge, issues:) if @candidate_limit
          cherry = reason ? [] : selected.map { |finding| format_repair(finding) }.uniq
          ideas = { ideas: candidates.map { |finding| format_repair(finding) }, final: judge[:feedback] }
          visual_clean = !reason && @mode[:preset_key] == "ui_critique" && issues.empty? && cherry.empty?
          status = reason ? :inconclusive : :observed
          diversity = { requested: @candidate_limit, distinct: candidates.size, comparison_rounds: judge[:comparison_rounds], method: :anchored_lexical_overlap }
          @bus&.publish(@mode[:done_event], status:, diversity:, cherry_picks: cherry.size, visual_clean:)
          harvest = harvest_path(payload:, feedback:, ideas:, cherry:, reason:) if @harvest
          Master::Result.ok({
            feedback:,
            issues:,
            visual_clean:,
            ideas:,
            cherry_picks: cherry,
            diversity:,
            status:,
            reason:,
            metrics: payload[:metrics],
            coverage: payload[:coverage],
            mode: @mode[:preset_key],
            harvest:,
          })
        end

        def selection_error(candidates, selected, judge, issues:)
          if candidates.size < @candidate_limit && (issues.any? || selected.any?)
            return "candidate exploration incomplete: #{candidates.size}/#{@candidate_limit} distinct proposals"
          end
          return if candidates.empty?

          verdicts = Array(judge[:position_evidence]).filter_map do |entry|
            index = entry["location"].to_s[/\Acandidate ([1-9]\d*)\z/i, 1]&.to_i
            verdict = entry["evidence"].to_s[/\A(KEEP|REJECT):\s*\S/i, 1]&.upcase
            [index, verdict] if index && verdict
          end
          ids = (1..candidates.size).to_a
          return "judge did not assess each candidate exactly once" unless verdicts.map(&:first).sort == ids

          eligible = verdicts.filter_map do |index, verdict|
            CherryPick.repair_key(candidates.fetch(index - 1)) if verdict == "KEEP"
          end
          return "judge selected a rejected or unreviewed repair" unless selected.all? { |finding| eligible.include?(CherryPick.repair_key(finding)) }

          nil
        end

        def format_repair(finding)
          finding.values_at("location", "claim", "proposed_repair").join(" — ").gsub(/\s+/, " ")
        end

        def deliberate(panel, payload)
          required_veto_roles = @mode[:preset_key] == "general_critique" ? ["Security"] : []
          Tribunal.new(
            agent: @agent,
            event_bus: @bus,
            judge_enabled: true,
            speak_personas: @speak_personas,
            candidate_limit: @candidate_limit,
          ).review(
            evidence: evidence_for(payload),
            personas: panel,
            context: build_context,
            image: payload[:visual_image],
            required_veto_roles:,
          )
        end

        def feedback_inconclusive?(feedback)
          feedback.is_a?(Hash) && feedback[:status].to_s == "inconclusive"
        end

        def inconclusive_run_result(payload, feedback)
          Master::Result.ok({
            feedback:,
            issues: [],
            visual_clean: false,
            ideas: [],
            cherry_picks: [],
            metrics: payload[:metrics],
            coverage: payload[:coverage],
            mode: @mode[:preset_key],
            harvest: nil,
            status: :inconclusive,
            reason: feedback[:reason],
          })
        end

        def evidence_for(payload)
          files = Array(payload[:files]).map(&:to_s)
          observations = payload[:combined].to_s.strip
          Evidence.new(
            artifact: @mode[:preset_key],
            domain: @mode[:quality_kind],
            status: observations.empty? ? :inconclusive : :observed,
            observations: observations.empty? ? [] : [observations],
            measurements: payload[:metrics] || {},
            structure: { file_count: files.size },
            anchors: files,
            provenance: { files: },
          )
        end

        def panel_issue_entries(feedback)
          Array(feedback).reject { |entry| entry[:persona] == "Judge" }.flat_map do |entry|
            Array(entry[:structured_findings]).select { |finding| CherryPick.actionable?(finding) }.map do |finding|
              { persona: entry[:persona], summary: finding["claim"], feedback: finding["evidence"], location: finding["location"] }
            end
          end.uniq { |issue| issue.values_at(:location, :summary) }.first(12)
        end

        def harvest_path(payload:, feedback:, ideas:, cherry:, reason:)
          Harvest.write(
            mode: @mode[:preset_key],
            files: payload[:files],
            feedback:,
            ideas:,
            cherry:,
            reason:,
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Critique.harvest", severity: :load_bearing)
          nil
        end

        # Extra images ride on the primary image's :extra list, so the one-image
        # contract through Tribunal, Deliberation and the dispatcher is unchanged.
        def with_extra_images(primary, extras)
          extras = Array(extras).compact
          return primary if extras.empty?
          return primary.merge(extra: Array(primary[:extra]) + extras) if primary

          extras.first.merge(extra: extras.drop(1))
        end

        def build_context
          base = Context.new(preset_key: @mode[:preset_key], quality_kind: @mode[:quality_kind]).to_s
          taste = @mode[:preset_key] == "ui_critique" ? Master::Fix::TasteMemory.summary(Master::ROOT) : nil
          constraints = @mode[:constraints].join("\n- ") if @candidate_limit
          [base, constraints && "Preserve these constraints:\n- #{constraints}",
           @briefing.empty? ? nil : "REVIEW BRIEFING\n#{@briefing}", taste].compact.join("\n\n")
        end

        def load_preset
          return {} unless File.exist?(Master::COUNCIL_PATH)
          data = Master.load_yaml(Master::COUNCIL_PATH) || {}
          # A pin selects its own yaml panel (simplify_critique, security_critique)
          # so the pin narrows the panel, not only the briefing text. An unknown
          # preset name falls back to the mode's own preset, and a preset without
          # files keeps the mode's file window.
          key = pin_preset_key || @mode[:preset_key]
          data.dig("presets", key) || {}
        end

        def pin_preset_key
          return unless defined?(Master::Fix::CritiquePin)

          pin = Master::Fix::CritiquePin
          return "simplify_critique" if pin.simplify?
          return "security_critique" if pin.security?

          nil
        end

        def build_panel(preset)
          all = Personas.load
          names = Array(preset["panel"] || @mode[:panel]).map(&:downcase)
          panel = if names.empty?
                    all
                  else
                    chosen = all.select { |persona| names.include?(persona.name.downcase) }
                    chosen.empty? ? Personas::DEFAULTS : chosen
                  end
          panel = contextual_panel(panel, all) if @mode[:preset_key] == "general_critique" && !pin_preset_key
          localize_panel(panel)
        end

        # Prefer relevant specialists without removing configured veto reviewers.
        def contextual_panel(panel, all)
          paths = Array(@files_override).map(&:to_s)
          names = []
          names.concat(%w[Typographer] + ["Graphic Designer", "Web Designer", "Accessibility"]) if paths.any? { |path| path.match?(%r{\.(?:css|scss|html|erb|svg)\z}i) }
          names.concat(["Sound Engineer", "Hip-Hop Producer", "Sound Designer"]) if paths.any? { |path| path.match?(%r{(?:/|\A)dilla/|\.(?:wav|flac|mid|mp3)\z}i) }
          names.concat(["Photographer", "Colourist", "Cinematographer", "Graphic Designer", "Design Lead"]) if paths.any? { |path| path.match?(%r{(?:/|\A)(?:photography|cinema|lora|postpro|replicate)(?:/|\z)|\.(?:png|jpe?g|webp|mov|mp4)\z}i) }
          names << "Film Editor" if paths.any? { |path| path.match?(%r{(?:motion|film|video)[^/]*\.rb\z|\.(?:mov|mp4)\z}i) }
          names << "Typographer" if paths.any? { |path| path.match?(%r{(?:/|\A)BIZ/|\.pdf\z}i) }
          specialists = names.uniq.filter_map { |name| all.find { |persona| persona.name == name } }
          veto = panel.select(&:veto?)
          (veto + specialists + panel).uniq
        end

        # Local-capacity sizing (see Deliberation.local_posture?): the full
        # 26-persona panel has exceeded the local review budget in measurement.
        # Local runs take council.yml's local_panel, with veto roles and the
        # Maintainer surviving the cut first. Re-measure before raising the cap.
        def localize_panel(panel)
          return panel unless Deliberation.local_posture?

          cap = Deliberation.local_panel_size
          return panel if panel.size <= cap

          keep = panel.select { |p| (p.respond_to?(:veto?) && p.veto?) || p.name == "Maintainer" }.first(cap)
          keep + (panel - keep).first([cap - keep.size, 0].max)
        end

        def build_payload(preset)
          files = if Array(@files_override).any?
                    @files_override
                  else
                    Array(preset["files"]).any? ? preset["files"] : @mode[:files]
                  end
          source_limit = @mode[:max_bytes]
          if @mode[:quality_kind] == :general && files.any?
            # Reserve room for the envelope and give every named source a share of the input.
            source_limit = (Deliberation::MAX_CODE_BYTES * 3 / 4) / files.size
          end
          sources = files.filter_map { |file| read_source(file, source_limit) }
          combined = sources.map { |source| source[:text] }.join("\n\n")
          metrics = mix_metrics_block if @mode[:include_mix_metrics]
          combined = [metrics, combined].compact.join("\n\n") if metrics
          combined = [@visual_context, combined].compact.join("\n\n") if @visual_context
          coverage = { supplied: files.size, read: sources.size, excerpts: sources.count { |row| row[:excerpt] } }
          { combined:, files:, metrics:, coverage:, visual_image: @visual_image }
        end

        def mix_metrics_block
          require_relative "../../voice/mix_metrics"
          path = @audio_path || Master::Voice::MixMetrics.first_existing_demo
          return "mix metrics: no demo.wav found (render one with /play first)" unless path

          Master::Voice::MixMetrics.brief(path)
        rescue StandardError => e
          "mix metrics unavailable: #{e.message}"
        end

        def read_source(rel, limit)
          # @files_override entries (whatever /scan or /fix just processed)
          # come in as absolute paths already; preset/mode file lists are
          # MASTER-root-relative.
          path = rel.to_s.start_with?("/") ? rel.to_s : File.join(Master::ROOT, rel)
          return unless File.file?(path)

          label = File.expand_path(path).delete_prefix("#{Master::REPO_ROOT}/")
          raw = File.binread(path, limit + 1).to_s
          return if raw.empty? || raw.include?("\0")

          excerpt = raw.bytesize > limit
          text = raw.byteslice(0, limit).force_encoding(Encoding::UTF_8).scrub
          { text: "file: #{label}\n#{text}#{"\n... [source excerpt]" if excerpt}", excerpt: }
        end
      end
    end
  end
end
