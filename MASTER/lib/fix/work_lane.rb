# frozen_string_literal: true

module Master
  module Fix
    # Which half of /fix a run does (not a model lane, Io::LaneSelection). A RAILS run once
    # rendered, researched and mapped for fifty minutes before a one-line RuboCop repair.
    module WorkLane
      # Lanes choose work depth; the Law and quality assessment remain universal. Standard
      # observes rendered RAILS surfaces, visual performs grouped RAILS repair, all combines
      # research/architecture/rendered review/grouped repair with every elevation stage, and
      # elevate concentrates on improvement, ideation and restructuring.
      NAMES = %i[code standard visual master all elevate].freeze
      DEFAULT = :code

      # The stages a lane may start. A stage absent from a lane's row is skipped and
      # named in the run's summary, so a code run never reads as visual proof.
      STAGES = {
        research: "research0 web research", architecture: "architecture exploration",
        layout_sweep: "layout sweep", browser_checks: "browser checks", screenshot_sweep: "screenshot sweep",
        visual_pass: "rendered visual review", code_passes: "code-law repair passes",
        visual_groups: "grouped visual repair", improve_code: "continuous polish discovery and repair",
        improve_prose: "prose elevation", improve_visual: "visual elevation",
        improve_music: "music elevation", ideate: "ideation", restructure_drive: "restructure drive",
        conversation: "conversation UX probe"
      }.freeze

      RUNS = {
        # conversation rides the code lane too (Johann 2026-11-08): the deterministic
        # conversation suite costs no model and no boot, and a /fix MASTER that never
        # asks how the replies read would claim the product while measuring only laws.
        code: %i[conversation code_passes improve_code],
        standard: %i[conversation layout_sweep browser_checks screenshot_sweep visual_pass code_passes improve_code],
        visual: %i[layout_sweep browser_checks screenshot_sweep visual_groups],
        master: %i[conversation visual_pass code_passes improve_code],
        all: %i[research architecture conversation layout_sweep browser_checks screenshot_sweep visual_pass visual_groups code_passes improve_code improve_prose improve_visual improve_music ideate restructure_drive],
        elevate: %i[improve_code improve_prose improve_visual improve_music ideate restructure_drive code_passes],
      }.freeze

      # RAILS apps and MASTER's own web face have rendered surfaces; other trees
      # do not acquire browser review merely because they contain text or media.
      @current = DEFAULT
      @lock = Mutex.new

      module_function

      # The default follows the actual rendered surface: RAILS apps and
      # MASTER's own web face earn the standard lane. BIZ remains a document
      # plane, and OPENBSD/STUDIO do not acquire browser review merely because
      # they contain text or media assets.
      def default_lane(target)
        # Same cut WorkLane.refusal uses: a path from anywhere in the checkout,
        # "/pub5/RAILS/mrdamascy" included, names its tree after the RAILS word.
        normalized = target.to_s.tr("\\", "/")
        relative = normalized.sub(%r{\A.*?(?=RAILS(?:/|\z))}i, "")
        rails = relative.upcase == "RAILS" || relative.upcase.start_with?("RAILS/")
        master_root = normalized.match?(%r{(?:\A|/)MASTER/?\z}i)
        master_web = normalized.match?(%r{(?:\A|/)MASTER/web(?:/|\z)}i)

        return :master if master_root || master_web

        rails ? :standard : DEFAULT
      end

      def rendered_target?(target)
        relative = target.to_s.sub(%r{\A.*?(?=RAILS(?:/|\z))}i, "")
        relative.upcase == "RAILS" || relative.upcase.start_with?("RAILS/")
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
        line += "; rendered findings are not measured or proven by this run" unless runs?(:layout_sweep, lane) || runs?(:visual_pass, lane)
        line += "; elevation improves toward the ideal and never blocks a run" if elevate?(lane)
        line
      end
    end
  end
end
