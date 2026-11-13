# frozen_string_literal: true

require "cgi"
require "digest"
require "erb"
require "fileutils"
require "json"
require "time"
require "tmpdir"
require_relative "../io/exec"
require_relative "screenshot_sweep/plan"
require_relative "screenshot_sweep/camera"
require_relative "screenshot_sweep/review_set"
require_relative "visual_runtime"
require_relative "../../checks/support/deploy_inventory"

module Master
  module Fix
    # Every page of every served app, at every declared sweep width, plus the
    # dialogs and sheets its controls open, kept on disk with an index. It
    # judges nothing: VisualPass reviews; this is the record of what rendered.
    #
    # Runs as the screenshot_sweep stage of the visual and all /fix lanes, and
    # alone through `bin/operator visual sweep`. MASTER_SCREENSHOT_SWEEP=0 opts out.
    class ScreenshotSweep
      GEOMETRY = File.join("MASTER", "checks", "data", "geometry_surfaces.yml")
      MAX_PAGES = Integer(ENV.fetch("MASTER_SCREENSHOT_SWEEP_MAX_PAGES", "600"))
      # A JSON or text route the manifest lists is skipped, not failed.
      NOT_A_PAGE = "skipped: not an HTML page"

      Row = Data.define(:app, :host, :path, :route, :status, :shots, :dialogs, :note) do
        def skipped? = note == NOT_A_PAGE
        def failed? = !note.nil? && !skipped?

        def verdict
          return "FAILED #{note}" if failed?

          skipped? ? note : "#{shots.size} widths, #{dialogs.size} dialogs"
        end
      end
      # What one app's pages share while they are captured.
      Visit = Data.define(:camera, :port, :frontier, :dialogs) do
        # Captures the surface and feeds its links back into the crawl.
        def shoot(surface, page_dir:)
          camera.take(surface, page_dir:, dialogs:).tap { |shot| frontier.learn(shot.links) }
        end
      end

      attr_reader :dir

      def initialize(root:, bus: nil, runtime: nil, out: nil, widths: nil)
        @root = root
        @bus = bus
        @runtime = runtime || VisualRuntime.new(root:, bus:)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        # Only a standing sweep refreshes the review set and prunes old sweeps.
        @standing = out.nil?
        # Captures land outside the repo (TREE_CONTRACTS: rendered artifacts live
        # under the system temp directory). The RAILS root holds the review set
        # itself, written flat by ReviewSet; a standing sweep adds no folder there.
        @dir = out || File.join(Dir.tmpdir, "pub5-screenshot-sweep", "sweep-#{stamp}")
        @plan = Plan.new(root:)
        available_widths = Array(YAML.safe_load_file(File.join(root, GEOMETRY)).fetch("sweep_widths")).map(&:to_i)
        @widths = Array(widths || available_widths).map(&:to_i).uniq
        raise ArgumentError, "sweep widths must be declared in geometry_surfaces.yml" if
          @widths.empty? || (@widths - available_widths).any?
      end

      def run(apps: nil, dialogs: true, max_pages: MAX_PAGES)
        apps = Array(apps).empty? ? Deploy::Inventory.new(root: @root).app_names : Array(apps)
        page_limit = Integer(max_pages).clamp(1, MAX_PAGES)
        boot = @runtime.ensure_running!(apps)
        return finish(apps:, rows: [], unresolved: {}, error: "apps not running: #{boot.message}") unless boot.ok?

        rows = []
        unresolved = {}
        Deploy::GeometryProbe.with_browser(root: @root, warm: []) do |cdp|
          camera = Camera.new(cdp:, widths: @widths, dir: @dir)
          apps.each { |app| unresolved[app] = sweep_app(app, camera:, rows:, dialogs:, max_pages: page_limit) }
        end
        finish(apps:, rows:, unresolved:)
      ensure
        @runtime.stop_owned!
      end

      private

      # Appends one Row per visited page; returns the routes nothing reached.
      def sweep_app(app, camera:, rows:, dialogs:, max_pages:)
        port = Deploy::GeometryProbe.app_ports(root: @root)[app]
        visit = Visit.new(camera:, port:, frontier: Frontier.new(@plan, app), dialogs:)
        max_pages.times do
          page = visit.frontier.next_page or break
          rows << capture(page, visit).tap { |row| progress(rows.size + 1, row) }
        end
        visit.frontier.unresolved
      end

      def capture(page, visit)
        page_dir = File.join(@dir, page.app, slugify(page.key))
        shot = visit.shoot(surface_for(page, port: visit.port), page_dir:)
        Row.new(**page.to_h, status: shot.status, shots: shot.widths, dialogs: shot.dialogs,
                             note: shot.html ? nil : NOT_A_PAGE)
      rescue StandardError => e
        failed(page, "#{e.class.name.split("::").last}: #{e.message}")
      end

      # One line per page as it lands, so a long sweep is watchable and a failure shows at once.
      def progress(count, row)
        warn("shots0: #{count} #{row.app} #{row.host}#{row.path} HTTP #{row.status || "?"} #{row.verdict}")
      end

      def failed(page, note) = Row.new(**page.to_h, status: nil, shots: {}, dialogs: [], note:)

      def surface_for(page, port:)
        width = Camera::DIALOG_WIDTH
        Deploy::GeometryProbe::Surface.new(
          app: page.app, label: slugify(page.key), host: page.host, path: page.path, viewport: "w#{width}",
          width:, height: Camera.height(width), snapshot: false, pixel_snapshot: false, port:
        )
      end

      def finish(apps:, rows:, unresolved:, error: nil)
        FileUtils.mkdir_p(@dir)
        summary = totals(rows).merge(
          "generated_at" => Time.now.utc.iso8601, "revision" => checkout_revision,
          "directory" => @dir, "apps" => apps, "widths" => @widths, "error" => error,
          "unresolved" => unresolved, "rows" => rows.map(&:to_h)
        )
        File.write(File.join(@dir, "index.json"), JSON.pretty_generate(summary))
        File.write(File.join(@dir, "index.html"), Gallery.new(summary, dir: @dir).render)
        refresh_review_set(rows) if @standing && error.nil?
        @bus&.publish("fix_loop:screenshot_sweep", dir: @dir, **totals(rows).transform_keys(&:to_sym))
        summary
      end

      def checkout_revision
        output, status = Master::Io::Exec.capture2e("git", "rev-parse", "--verify", "HEAD", chdir: @root, timeout: 5)
        revision = output.to_s.strip
        revision if status&.success? && revision.match?(/\A[0-9a-f]{40}\z/i)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "screenshot_sweep.checkout_revision")
        nil
      end

      def refresh_review_set(rows)
        review = ReviewSet.new(root: @root, sweep_dir: @dir)
        copied = review.publish!(rows)
        pages = Gallery.publish_review_page(root: @root)
        warn("shots0: review set RAILS/screenshot_*.png, #{copied} pages; #{pages} in RAILS/#{Gallery::REVIEW_PAGE}; " \
             "pruned #{review.prune!} old sweeps")
      end

      def totals(rows)
        {
          "pages" => rows.size,
          "screenshots" => rows.sum { |row| row.shots.size },
          "dialogs" => rows.sum { |row| row.dialogs.size },
          "failed" => rows.count(&:failed?),
          "skipped" => rows.count(&:skipped?)
        }
      end

      def slugify(text)
        slug = text.to_s.gsub(/[^A-Za-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
        slug.empty? ? "root" : slug
      end

      # One self-contained page over the index: per app, per page, a swipeable
      # strip of every width and every captured dialog. It loads nothing from the
      # network; the markup is screenshot_sweep/gallery.html.erb, and its
      # stylesheet and script are inlined so the single index.html can be opened
      # or sent on its own. Gallery.publish_review_page renders the same page
      # over the tracked RAILS/ set as RAILS/screenshots.html. Only a standing
      # sweep's folder carries an install manifest beside its index.html.
      class Gallery
        TEMPLATE = ERB.new(File.read(File.join(__dir__, "screenshot_sweep", "gallery.html.erb")), trim_mode: "<>")
        STYLESHEET = File.join(__dir__, "screenshot_sweep", "gallery.css")
        SCRIPT = File.join(__dir__, "screenshot_sweep", "gallery.js")
        # What ReviewSet publishes, and the only identity the published set
        # carries: screenshot_<app>_<page>.png.
        REVIEW_SHOT = /\Ascreenshot_(?<app>[A-Za-z0-9]+)_(?<page>.+)\.png\z/
        REVIEW_PAGE = "screenshots.html"

        # Render the published gallery over the tracked shots in RAILS/. This is
        # the single file the operator opens or sends: it inlines its own CSS and
        # script, so it needs only the sibling PNGs and nothing else.
        def self.publish_review_page(root:, at: Time.now.utc.iso8601)
          rails = File.join(root, "RAILS")
          names = Dir.children(rails).grep(REVIEW_SHOT).sort
          grouped = names.group_by { |name| REVIEW_SHOT.match(name)&.[](:app) || "unknown" }
          rows = grouped.sort_by(&:first).map do |app, files|
            {
              app: app.downcase, host: nil, path: "review set",
              route: "#{files.size} captured pages", status: nil,
              shots: {}, dialogs: files, note: nil
            }
          end
          summary = {
            "generated_at" => at, "pages" => names.size, "screenshots" => names.size,
            "dialogs" => 0, "failed" => 0, "skipped" => 0, "widths" => [ReviewSet::WIDTH],
            "error" => nil, "unresolved" => {}, "rows" => rows
          }
          File.write(File.join(rails, REVIEW_PAGE), new(summary, dir: rails).render)
          names.size
        end

        attr_reader :summary

        def initialize(summary, dir: nil)
          @summary = summary
          @dir = dir
        end

        def render = TEMPLATE.result(binding)

        def stylesheet = File.read(STYLESHEET)

        def script = File.read(SCRIPT)

        def rows = Array(summary["rows"])

        def unresolved = Hash(summary["unresolved"]).reject { |_app, routes| Array(routes).empty? }

        # One entry per page with its figures already collapsed against every
        # other page: a shot byte-identical to one shown earlier is dropped and
        # its page named on the copy that stays, so near-identical states do not
        # pad the strips. A page left with no unique shot keeps its heading and
        # says so.
        def pages
          @pages ||= build_pages
        end

        def escape(value) = CGI.escapeHTML(value.to_s)

        private

        # [file, caption] pairs: widths first, then the dialogs.
        def figures(row)
          widths = row.fetch(:shots).map { |width, file| [file, "#{width}px"] }
          widths + row.fetch(:dialogs).map { |file| [file, File.basename(file, ".png").delete_prefix("screenshot_")] }
        end

        def build_pages
          seen = {}
          rows.map do |row|
            unique = figures(row).filter_map do |file, caption|
              digest = digest_of(file)
              if digest && seen.key?(digest)
                seen.fetch(digest)[:aliases] << identity(row, caption)
                nil
              else
                entry = { file:, caption:, aliases: [] }
                seen[digest] = entry if digest
                entry
              end
            end
            { app: row[:app], host: row[:host], path: row[:path], route: row[:route],
              status: row[:status], note: row[:note], figures: unique }
          end
        end

        def identity(row, caption) = "#{row[:app]} #{row[:host]}#{row[:path]} #{caption}"

        def digest_of(file)
          return unless @dir

          path = File.join(@dir, file)
          return unless File.file?(path)

          Digest::SHA256.file(path).hexdigest
        end
      end
    end
  end
end
