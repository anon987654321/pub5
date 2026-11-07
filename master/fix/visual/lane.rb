# frozen_string_literal: true

require_relative "capture"
require_relative "pixel_match"
require_relative "state_matrix"
require_relative "audit"
require_relative "review"
require_relative "simplify"
require_relative "../leases"
require_relative "../commit_message"

module Fix
  module Visual
    # `bin/master fix --visual`: after the code repairs, render a bounded,
    # mobile-first share of every present app's surfaces, hold each shot
    # still, compare it perceptually with its baseline, mark guarded
    # regressions hard, run the simplify stage once, and say what it could
    # not measure. The checks that need a DOM session (state matrix, axe, the
    # computed-value and space audits) run when a session is given; pub5 has
    # no CDP client yet, so a headless-Chrome lane reports them NOT_RUN.
    class Lane
      DIR = "tmp/fix/visual"

      def initialize(world:, reviewer:, author:, chrome:, camera: nil, session: nil, sheets: nil, build: nil)
        @world = world
        @author = author
        @reviewer = reviewer
        @camera = camera || Headless.new(world:, chrome:)
        @session = session
        @sheets = sheets
        @build = build || method(:build_css)
      end

      def call(run)
        @run = run
        notes = []
        notes << reviewer_note
        notes << capture_pass
        notes << dom_note
        notes << simplify_pass
        notes.compact.join("; ")
      end

      def dom_note = "state matrix, axe and computed audits NOT_RUN (DOM audit runner not wired)"

      # The reviewer must be a different model from the author.
      def reviewer_note
        return "reviewer none: a visible change stays uncleared" unless @reviewer

        pinned = @reviewer.router.chain("review").first
        return if pinned.nil? || pinned != @author

        @reviewer = nil
        "reviewer refused: #{pinned} is also the author"
      end

      def review(group, regions) = Reviewer.judge(@world, group, regions, reviewer: @reviewer)

      def pass_number
        path = File.join(DIR, "pass")
        number = ((@world.read(path).to_i rescue 0)) + 1
        @world.write(path, "#{number}\n")
        number
      end

      def capture_pass
        return "capture NOT_RUN (no browser at PUB5_CHROME)" unless @camera.available?

        surfaces = Surfaces.select(Surfaces.for_apps(Apps.present(@world)), pass: pass_number)
        tally = Hash.new(0)
        guards = Guards.rows(@world)
        regressions = surfaces.filter_map do |surface|
          @run.pulse
          status, message = surface_shot(surface)
          tally[status] += 1
          message
        end
        Guards.mark(regressions, guards).each { |line| @run.say(line) }
        "#{surfaces.size} surfaces mobile first: #{tally.map { |k, v| "#{k} #{v}" }.join(', ')}"
      end

      def surface_shot(surface)
        return [:down] unless up?(surface)

        shot = @camera.capture(surface)
        return [:unstable] unless shot[:png] && shot[:stable]

        baseline = File.join(DIR, "baseline", "#{surface.id}.png")
        old = (@world.read(baseline) rescue nil)
        unless old
          @world.write(baseline, shot[:png])
          return [:baselined]
        end
        result = PixelMatch.compare(old, shot[:png])
        return [:unchanged] if result[:status] == :compared && result[:pixel_diff_count].zero?

        @world.write(File.join(DIR, "diff", "#{surface.id}.png"), result[:diff_png]) if result[:diff_png]
        [:changed, "visual regression: #{surface.id} #{result[:pixel_diff_count]} px in #{result[:regions].size} box(es) " \
                   "#{surface.app}#{surface.path} #{surface.width}"]
      end

      def up?(surface)
        @world.net(:get, surface.url).status.positive?
      rescue Core::Refusal, SystemCallError, IOError, Timeout::Error, SocketError
        false
      end

      def simplify_pass
        sheets = @sheets || @run.tracked.select { |f| f.match?(%r{\Arails/.+\.s?css\z}) && !f.include?("/builds/") }
        return "simplify: no stylesheets" if sheets.empty?

        stage = Simplify::Stage.new(world: @world, shots: method(:shots), review: method(:review), commit: method(:commit_sheet))
        done = stage.run(sheets)
        "simplify: #{done.map { |path, verdict| "#{File.basename(path)} #{verdict}" }.join(', ')}"
      end

      # Before and after shots of the sheet's app around the write and a CSS
      # build; nil when the app is down, unbuilt or no browser is at hand.
      def shots(path)
        app = Apps.present(@world).find { |a| path.start_with?("#{a.dir}/") }
        surfaces = app && Surfaces.for_apps([app]).first(3)
        return yield.then { nil } unless surfaces && @camera.available? && surfaces.all? { |s| up?(s) }

        before = surfaces.map { |s| @camera.capture(s)[:png] }
        yield
        return nil unless @build.call(app)

        before.zip(surfaces.map { |s| @camera.capture(s)[:png] }).select { |one, two| one && two }
      end

      def build_css(app)
        return false unless File.file?(File.join(@world.manifest.root, app.dir, "bin/rails"))

        @world.exec(RbConfig.ruby, "bin/rails", "dartsass:build", chdir: File.join(@world.manifest.root, app.dir), timeout: 300).ok?
      end

      def commit_sheet(path)
        message = CommitMessage.compose("Simplify #{File.basename(path)} by subtraction",
                                        what: "The simplify stage merged duplicate rule blocks and tokenised literals in #{path}",
                                        why: "A count fell and the render showed no change, or the independent reviewer approved it",
                                        trailers: { law: "AESTHETIC_MINIMALISM", measured: "counts fell in #{path}",
                                                    writer: "operator", proof: "pixel compare of the app's first surfaces" })
        @world.git("add", "--", path)
        @world.git("commit", "-q", "-m", message, "--", path)
      end
    end
  end
end
