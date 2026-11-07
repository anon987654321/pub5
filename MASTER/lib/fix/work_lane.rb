# frozen_string_literal: true

module Master
  module Fix
    # Which half of /fix a run does (not a model lane, Io::LaneSelection). A RAILS run once
    # rendered, researched and mapped for fifty minutes before a one-line RuboCop repair.
    module WorkLane
      # code: code laws only, no claim about anything rendered. standard (the bare default on a
      # rendered target, Johann 2026-11-07): code laws PLUS the rendered observation — layout sweep,
      # browser checks, screenshot sweep, rendered visual review — so a plain "/fix RAILS/..." sees
      # the pages before and after its repairs without anyone asking for it. visual (RAILS only,
      # explicit): one sweep grouped by cause, mechanical fixers first. all: both plus research and
      # architecture, as /fix ran before lanes. elevate: the improvement lane — /fix does not only
      # repair, it improves, ideates and restructures toward each domain's ideal (code, prose,
      # visual, music) per laws.yml.
      NAMES = %i[code standard visual all elevate].freeze
      DEFAULT = :code

      # The stages a lane may start. A stage absent from a lane's row is skipped and
      # named in the run's summary, so a code run never reads as visual proof.
      STAGES = {
        research: "research0 web research", architecture: "architecture exploration",
        layout_sweep: "layout sweep", browser_checks: "browser checks", screenshot_sweep: "screenshot sweep",
        visual_pass: "rendered visual review", code_passes: "code-law repair passes",
        visual_groups: "grouped visual repair", improve_code: "code elevation",
        improve_prose: "prose elevation", improve_visual: "visual elevation",
        improve_music: "music elevation", ideate: "ideation", restructure_drive: "restructure drive"
      }.freeze

      RUNS = {
        code: %i[code_passes],
        standard: %i[layout_sweep browser_checks screenshot_sweep visual_pass code_passes],
        visual: %i[layout_sweep browser_checks screenshot_sweep visual_groups],
        all: %i[research architecture layout_sweep browser_checks screenshot_sweep visual_pass code_passes],
        elevate: %i[improve_code improve_prose improve_visual improve_music ideate restructure_drive code_passes],
      }.freeze

      # The bare default a target earns: a rendered surface (RAILS) gets the standard lane —
      # rendered findings were invisible to a plain /fix until Johann asked (2026-11-07) why a
      # run produced no screenshots; every other tree has nothing to render and keeps code.
      @current = DEFAULT
      @lock = Mutex.new

      module_function

      # The bare default a target earns: a rendered surface (RAILS; RAILS' apps.yml
      # declares the deploy roots, master lives at MASTER/web) gets the standard lane —
      # rendered findings were invisible to a plain /fix until Johann asked (2026-11-07)
      # why a run produced no screenshots. Every other tree has nothing to render and
      # keeps code.
      def default_lane(target)
        # Same cut WorkLane.refusal uses: a path from anywhere in the checkout,
        # "/pub5/RAILS/mrdamascy" included, names its tree after the RAILS word.
        relative = target.to_s.sub(%r{\A.*?(?=RAILS(?:/|\z))}i, "")
        rendered = relative.upcase == "RAILS" || relative.upcase.start_with?("RAILS/")

        rendered ? :standard : DEFAULT
      end

      def current = @lock.synchronize { @current }

      def set!(name) = @lock.synchronize { @current = parse(name) }

      def restore(name) = @lock.synchronize { @current = name }

      def parse(name)
        lane = name.to_s.strip.downcase.to_sym
        return lane if NAMES.include?(lane)

        raise ArgumentError, "unknown lane #{name.inspect}; one of #{NAMES.join(", ")}"
      end

      def runs?(stage, lane = current) = RUNS.fetch(lane).include?(stage)

      def skipped(lane = current) = (STAGES.keys - RUNS.fetch(lane)).map { |stage| STAGES.fetch(stage) }

      def visual?(lane = current) = lane == :visual

      # The elevate lane improves every tree — code, prose, visuals, music — and
      # only the visual elevation reads RAILS render surfaces.
      def elevate?(lane = current) = lane == :elevate

      # The visual lane measures the RAILS apps; every other tree has nothing to render.
      def refusal(target, lane = current)
        return unless visual?(lane)

        relative = target.to_s.sub(%r{\A.*?(?=RAILS(?:/|\z))}, "")
        return if relative == "RAILS" || relative.start_with?("RAILS/")

        "--lane visual renders the RAILS apps; #{target} has no rendered surface"
      end

      # The child check runner reads this: CHECK_LANE=code leaves its browser checks out.
      def check_env(lane = current) = { "CHECK_LANE" => lane.to_s }

      def summary(lane = current)
        skipped = skipped(lane)

        line = "lane=#{lane}"
        line += ", skipped: #{skipped.join(", ")}" unless skipped.empty?
        line += "; rendered findings are not measured or proven by this run" unless runs?(:layout_sweep, lane)
        line += "; elevation improves toward the ideal and never blocks a run" if elevate?(lane)
        line
      end
    end
  end
end
