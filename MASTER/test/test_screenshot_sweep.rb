# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../lib/fix/work_lane"
require_relative "../lib/fix/screenshot_sweep"

# The screenshot sweep's page plan, its lane wiring and its no-browser failure
# path. Rendering itself needs Chrome and booted apps; `bin/operator visual
# sweep` is that proof, and its index.json is the evidence.
class TestScreenshotSweep < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def with_manifest(routes)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "MASTER", "checks", "data"))
      File.write(File.join(dir, Master::Fix::ScreenshotSweep::Plan::MANIFEST), { "apps" => routes }.to_yaml)
      yield Master::Fix::ScreenshotSweep::Plan.new(root: dir)
    end
  end

  def test_seeds_are_pages_with_the_root_first_and_machine_endpoints_left_out
    with_manifest("amber" => { "routes" => {
      "a" => ["/terms"], "b" => ["/manifest.json", "/.well-known/assetlinks.json", "/up"],
      "c" => ["/service-worker.js", "/api/v1/lint", "/posts/:id"], "d" => ["/"]
    } }) do |plan|
      assert_equal %w[/ /terms], plan.seeds("amber").map(&:path)
    end
  end

  def test_an_app_without_manifest_routes_is_swept_at_its_root
    with_manifest({}) { |plan| assert_equal ["/"], plan.seeds("master").map(&:path) }
  end

  def test_parameter_routes_become_patterns_and_catch_alls_are_dropped
    routes = { "a" => ["/posts/:id", "/posts/:id/edit", "/:slug", "/files/*path"] }
    with_manifest("amber" => { "routes" => routes }) do |plan|
      patterns = plan.patterns("amber")

      assert_equal ["/posts/:id", "/posts/:id/edit", "/files/*path"], patterns.keys
      assert_match patterns["/posts/:id"], "/posts/42"
      refute_match patterns["/posts/:id"], "/posts/42/edit"
      assert_match patterns["/files/*path"], "/files/a/b.pdf"
    end
  end

  def test_brgen_is_planned_on_its_apex_and_every_vertical_host
    plan = Master::Fix::ScreenshotSweep::Plan.new(root: ROOT)
    hosts = plan.seeds("brgen").map(&:host).uniq

    assert_includes hosts, "brgen.no"
    assert_includes hosts, "markedsplass.brgen.no"
    assert_includes hosts, "maps.brgen.no"
  end

  # The engines mount at / on their own subdomains; asking the apex for /feed
  # returns the routing-error page, not tv's feed.
  def test_brgen_engine_routes_are_planned_on_their_engine_subdomain
    plan = Master::Fix::ScreenshotSweep::Plan.new(root: ROOT)
    hosts = plan.seeds("brgen").to_h { |page| [[page.path, page.host], true] }

    assert hosts[["/feed", "tv.brgen.no"]], "tv/feed#index belongs on tv.brgen.no"
    assert hosts[["/profile/new", "dating.brgen.no"]], "dating/profiles#new belongs on dating.brgen.no"
    assert hosts[["/shops", "markedsplass.brgen.no"]], "marketplace/stores#index belongs on a marketplace alias"
    refute hosts[["/feed", "brgen.no"]], "the apex has no /feed"
  end

  def test_the_stage_runs_in_the_rendering_lanes_and_not_the_code_lane
    assert Master::Fix::WorkLane.runs?(:screenshot_sweep, :visual)
    assert Master::Fix::WorkLane.runs?(:screenshot_sweep, :all)
    refute Master::Fix::WorkLane.runs?(:screenshot_sweep, :code)
    assert_includes Master::Fix::WorkLane.skipped(:code), "screenshot sweep"
  end

  def test_startup_placeholder_is_failed_instead_of_published_as_a_render
    cdp = Object.new
    def cdp.viewport(*) = nil
    def cdp.navigate(*) = nil
    def cdp.status = 200
    def cdp.evaluate(script)
      return "text/html" if script == "document.contentType"
      return true if script.include?("starting up")

      false
    end

    camera = Master::Fix::ScreenshotSweep::Camera.new(cdp:, widths: [390], dir: Dir.tmpdir)
    surface = Struct.new(:url).new("http://127.0.0.1:38182/")
    Dir.mktmpdir do |page_dir|
      shot = camera.take(surface, page_dir:, dialogs: false)

      assert shot.html
      assert_empty shot.widths
      assert_match(/startup placeholder/, shot.note)
    end
  end

  def test_uniform_screenshot_is_failed_instead_of_published_as_a_render
    camera = Master::Fix::ScreenshotSweep::Camera.allocate
    Dir.mktmpdir do |dir|
      blank = File.join(dir, "blank.png")
      image = File.join(dir, "image.png")
      Vips::Image.black(8, 8).write_to_file(blank)
      Vips::Image.new_from_array([[0, 255], [255, 0]]).write_to_file(image)

      assert camera.send(:blank_frame?, blank)
      refute camera.send(:blank_frame?, image)
    end
  end

  def test_failed_rows_never_replace_the_tracked_review_set
    Dir.mktmpdir do |root|
      rails = File.join(root, "RAILS")
      sweep_dir = File.join(root, "sweep")
      source = File.join(sweep_dir, "master", "root", "390.png")
      FileUtils.mkdir_p(File.dirname(source))
      FileUtils.mkdir_p(rails)
      File.binwrite(source, "startup placeholder")
      old = File.join(rails, "screenshot_master_previous.png")
      File.binwrite(old, "previous review")

      row = Struct.new(:app, :shots, :note).new(
        "master", { "390" => "master/root/390.png" }, "startup placeholder"
      )
      review = Master::Fix::ScreenshotSweep::ReviewSet.new(root:, sweep_dir:)

      assert_equal 0, review.publish!([row])
      refute File.exist?(File.join(rails, "screenshot_master_root.png"))
      refute File.exist?(old), "a failed sweep clears stale review evidence"
    end
  end

  def test_the_sweep_widths_are_declared_data
    widths = YAML.safe_load_file(File.join(ROOT, Master::Fix::ScreenshotSweep::GEOMETRY)).fetch("sweep_widths")

    assert_equal [320, 360, 375, 390, 430, 480, 640, 768, 1024, 1280], widths
  end

  FailedBoot = Struct.new(:message) do
    def ok? = false
    def ensure_running!(_apps) = self
    def stop_owned! = nil
  end

  def test_standing_sweep_captures_outside_the_repo_and_records_revision_field
    Dir.mktmpdir("screenshot-root") do |root|
      FileUtils.mkdir_p(File.dirname(File.join(root, Master::Fix::ScreenshotSweep::GEOMETRY)))
      FileUtils.cp(File.join(ROOT, Master::Fix::ScreenshotSweep::GEOMETRY),
                   File.join(root, Master::Fix::ScreenshotSweep::GEOMETRY))
      File.write(File.join(root, Master::Fix::ScreenshotSweep::Plan::MANIFEST), { "apps" => {} }.to_yaml)

      sweep = Master::Fix::ScreenshotSweep.new(root:, runtime: FailedBoot.new("not started"))
      refute sweep.dir.start_with?(root),
             "raw captures must not create a folder inside the checkout"
      assert_match(%r{/pub5-screenshot-sweep/sweep-\d{8}T\d{6}Z\z}, sweep.dir)

      sweep.run(apps: ["bsdports"])
      index = JSON.parse(File.read(File.join(sweep.dir, "index.json")))
      assert index.key?("revision"), "index declares revision even when checkout identity is unavailable"
      assert_equal sweep.dir, index["directory"]
    end
  end

  def test_one_page_mode_can_restrict_capture_width_and_page_count
    Dir.mktmpdir("screenshot-one-page") do |out|
      summary = Master::Fix::ScreenshotSweep.new(
        root: ROOT, runtime: FailedBoot.new("not started"), out:, widths: [390],
      ).run(apps: ["bsdports"], dialogs: false, max_pages: 1)

      assert_equal [390], summary["widths"]
      assert_equal 0, summary["screenshots"]
    end
  end

  def test_sweep_reports_a_page_before_its_capture_completes
    page = Master::Fix::ScreenshotSweep::Plan::Page.new(
      app: "brgen", host: "brgen.no", path: "/", route: "root"
    )
    output, error = capture_io { Master::Fix::ScreenshotSweep.allocate.send(:progress_start, 7, page) }

    assert_empty output
    assert_equal "shots0: 7 brgen brgen.no/ capture\n", error
  end

  def test_partial_standing_sweep_never_replaces_the_tracked_review_set
    Dir.mktmpdir("screenshot-root") do |root|
      rails = File.join(root, "RAILS")
      FileUtils.mkdir_p(File.dirname(File.join(root, Master::Fix::ScreenshotSweep::GEOMETRY)))
      FileUtils.cp(File.join(ROOT, Master::Fix::ScreenshotSweep::GEOMETRY),
                   File.join(root, Master::Fix::ScreenshotSweep::GEOMETRY))
      File.write(File.join(root, Master::Fix::ScreenshotSweep::Plan::MANIFEST), { "apps" => {} }.to_yaml)
      FileUtils.mkdir_p(rails)
      old = File.join(rails, "screenshot_master_previous.png")
      File.binwrite(old, "previous review")

      Master::Fix::ScreenshotSweep.new(root:, runtime: FailedBoot.new("not started")).run(apps: ["bsdports"])

      assert File.exist?(old), "a partial sweep must leave the curated review set intact"
    end
  end

  def test_apps_that_do_not_boot_leave_an_index_that_says_so
    Dir.mktmpdir do |out|
      summary = Master::Fix::ScreenshotSweep.new(root: ROOT, runtime: FailedBoot.new("port 47312 closed"), out:)
                                            .run(apps: ["bsdports"])

      assert_equal "apps not running: port 47312 closed", summary["error"]
      assert_equal 0, summary["screenshots"]
      assert_equal "apps not running: port 47312 closed", JSON.parse(File.read(File.join(out, "index.json")))["error"]
      assert_includes File.read(File.join(out, "index.html")), "port 47312 closed"
    end
  end

  Gallery = Master::Fix::ScreenshotSweep::Gallery

  def gallery_row(app:, path:, shots:, dialogs: [], status: 200)
    { app:, host: nil, path:, route: "#{path}#index", status:, shots:, dialogs:, note: nil }
  end

  def gallery_summary(rows)
    { "generated_at" => "2026-11-13T00:00:00Z", "pages" => rows.size, "screenshots" => 0,
      "dialogs" => 0, "failed" => 0, "skipped" => 0, "widths" => [390], "error" => nil,
      "unresolved" => {}, "rows" => rows }
  end

  # The gallery is a mobile-first carousel, not a wall of full-height images: one
  # scroll-snap rail per page, arrows and dots, and nothing fetched from the net.
  def test_gallery_renders_a_swipeable_carousel_with_no_network_asset
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "a.png"), "same")
      File.binwrite(File.join(dir, "b.png"), "other")
      rows = [gallery_row(app: "amber", path: "/a", shots: { "390" => "a.png", "980" => "b.png" })]
      html = Gallery.new(gallery_summary(rows), dir:).render

      assert_includes html, %(name="viewport")
      assert_includes html, "data-strip", "each page carries a scroll-snap rail"
      assert_includes html, %(data-step="-1")
      assert_includes html, "data-dots"
      assert_includes html, "data-position"
      assert_includes html, "<style>"
      assert_includes html, "<script>"
      assert_includes html, 'loading="lazy"'
      refute_match(%r{(?:src|href)="https?://}, html, "the gallery loads nothing from the network")
    end
  end

  # Byte-identical shots collapse to one slide; the other page is named on it so
  # the review can see it was captured, without padding every strip.
  def test_gallery_collapses_identical_shots_and_names_the_alias
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "a.png"), "same")
      File.binwrite(File.join(dir, "b.png"), "same")
      File.binwrite(File.join(dir, "c.png"), "other")
      rows = [
        gallery_row(app: "amber", path: "/a", shots: { "390" => "a.png" }),
        gallery_row(app: "brgen", path: "/b", shots: { "390" => "b.png", "980" => "c.png" }),
      ]
      html = Gallery.new(gallery_summary(rows), dir:).render

      assert_equal 2, html.scan(%(class="slide")).size, "three figures collapse to two unique slides"
      assert_includes html, "identical on", "the dropped shot is named on the one that stays"
      assert_includes html, "brgen /b 390px"
    end
  end

  def test_gallery_marks_a_page_whose_every_shot_is_a_duplicate
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "a.png"), "same")
      File.binwrite(File.join(dir, "b.png"), "same")
      rows = [
        gallery_row(app: "amber", path: "/a", shots: { "390" => "a.png" }),
        gallery_row(app: "brgen", path: "/b", shots: { "390" => "b.png" }),
      ]
      html = Gallery.new(gallery_summary(rows), dir:).render

      assert_equal 1, html.scan(%(class="slide")).size
      assert_includes html, "No unique shot"
    end
  end

  # The operator's record is one file beside the tracked shots: RAILS/screenshots.html
  # inlines its own CSS and script and reads only its sibling PNGs.
  def test_publish_review_page_writes_a_self_contained_page_over_the_tracked_shots
    Dir.mktmpdir do |root|
      rails = File.join(root, "RAILS")
      FileUtils.mkdir_p(rails)
      { "screenshot_amber_account.png" => "amber",
        "screenshot_amber_orders.png" => "amber orders",
        "screenshot_brgen_brgen_no_groups_new.png" => "brgen" }.each do |name, body|
        File.binwrite(File.join(rails, name), body)
      end
      File.binwrite(File.join(rails, "keep_me.png"), "not a shot")

      assert_equal 3, Gallery.publish_review_page(root:, at: "2026-11-13T00:00:00Z")
      html = File.read(File.join(rails, "screenshots.html"))

      assert_includes html, "screenshot_amber_account.png"
      assert_includes html, "screenshot_brgen_brgen_no_groups_new.png"
      assert_includes html, "screenshot_amber_orders.png"
      refute_includes html, "keep_me.png", "only the tracked review shots are listed"
      refute_match(%r{(?:src|href)="https?://}, html)
      refute_includes html, %(rel="manifest"), "the published page needs nothing beside it"
      assert_includes html, "<style>"
      assert_includes html, "<script>"
      assert_equal 3, html.scan(%(class="slide")).size
      assert_equal 2, html.scan(%(class="strip")).size, "one carousel per app groups the review set"
    end
  end
end
