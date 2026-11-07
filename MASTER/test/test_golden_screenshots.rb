# frozen_string_literal: true

# The golden screenshots' rules, for a walk that runs against a real browser:
# the corpus is the route contract's 200 text/html rows, a dialog state is
# captured only where the page presents one (and an absent state is recorded,
# never skipped), and the check names a diff instead of overwriting what it
# compares against.

require "digest"
require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../checks/support/png_diff"
require_relative "../tools/rails/golden_screenshots"

class TestGoldenScreenshots < Minitest::Test
  TARGET = GoldenScreenshots::Target
  WHITE = "\xff\xff\xff\xff".b
  BLACK = "\x00\x00\x00\xff".b

  def png(color) = Deploy::PngDiff.encode_rgba(1, 1, color)

  def with_swap(name, replacement)
    original = GoldenScreenshots.method(name)
    GoldenScreenshots.define_singleton_method(name, replacement)
    yield
  ensure
    GoldenScreenshots.define_singleton_method(name, original)
  end

  # The row-key space: a pinned host and a loopback page, at each state.
  def keys
    {
      pinned: "dating.brgen.no|/likes|390|page",
      loopback: "|/account|390|page",
      dialog: "|/account|390|dialog",
    }
  end

  def compare_row(manifest_rows:, key:, fresh:, with_baseline: false, current: nil)
    target = GoldenScreenshots.target_from(key, "amber")
    baseline = @baseline = File.join(Dir.tmpdir, "golden-test-baseline-#{key.hash.abs}.png")
    capture_dir = @capture_dir = Dir.mktmpdir("golden-test-capture")
    if current
      path = File.join(capture_dir, "amber", target.slug)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, current)
    end
    # The live recording writes baselines into the real data dir; the unit
    # walk compares against its own tmp baseline.
    with_swap(:baseline_path, ->(_t) { baseline }) do
      File.binwrite(baseline, png(WHITE)) if with_baseline
      GoldenScreenshots.compare_row({ "rows" => manifest_rows }, key, "amber", fresh, capture_dir)
    end
  ensure
    FileUtils.remove_entry_secure(@capture_dir) if @capture_dir && Dir.exist?(@capture_dir)
    FileUtils.rm_f(@baseline) if @baseline && File.file?(@baseline)
  end

  # The volatile selectors (clocks, prices, relative times) are hidden by an
  # injected style: the check compares pixels, and this content changes
  # between runs by design.
  def test_the_mask_script_hides_the_contracts_volatile_selectors
    script = GoldenScreenshots.mask_script
    selectors = YAML.safe_load_file(GoldenScreenshots::GEOMETRY)["volatile_selectors"]

    assert_includes script, "visibility: hidden !important"
    assert_includes script, JSON.generate(selectors.join(", ") + " { visibility: hidden !important; }")
  end

  # A dialog state is captured only where the page presents an openable
  # surface: no dialog (or a failed show) is a skip, not a capture.
  def test_open_dialog_answers_only_when_the_surface_is_showable
    skip_cdp = Class.new do
      def initialize(answers) = @answers = answers
      def evaluate(...) = @answers.shift
    end

    assert_equal false, GoldenScreenshots.open_dialog(skip_cdp.new([nil])), "no openable surface"

    shown = skip_cdp.new(['"dialog"'])
    assert_equal true, GoldenScreenshots.open_dialog(shown), "a shown dialog captures its state"
  end

  def test_open_dialog_falls_back_to_a_popover_only_when_no_dialog_is_present
    # The JS is read as data here: dialog first, popover only in its absence.
    js = File.read(File.expand_path("../tools/rails/golden_screenshots.rb", __dir__))[/<<~JS\)\n(.+?)\n\s*JS\n/m, 1]

    assert_match(/if \(dialog\)/, js)
    assert_match(/querySelector\("\[popover\]:not\(\[open\]\)"\)/, js)
    assert_match(/checkVisibility/, js, "a zero-sized shown surface is not a dialog state")
  end

  def test_targets_pair_a_page_and_dialog_target_per_width_for_every_200_text_html_row
    contract = YAML.load_file(GoldenScreenshots.contract_path("bsdports"))
    golden = GoldenScreenshots.targets("bsdports", GoldenScreenshots::WIDTHS)
    pages = golden.reject(&:dialog)

    assert_equal contract["routes"].count { |_p, r| r["status"] == 200 && r["type"] == "text/html" } * GoldenScreenshots::WIDTHS.size, pages.size
    assert_equal pages.size, golden.size - pages.size, "every page state pairs with a dialog state"
    assert_equal 47312, pages.first.port
    assert pages.none?(&:host), "bsdports's contract pins no hosts"
    assert pages.map { |t| [t.path, t.width] }.tally.values.all? { |n| n == 1 }, "no page state repeats"
  end

  def test_the_slug_is_shell_safe_and_carries_host_width_and_dialog
    assert_equal "listings_SOFA_7__markedsplass.brgen.no__1280.png",
                 TARGET.new(app: "brgen", host: "markedsplass.brgen.no", path: "/listings/SOFA-7", width: 1280, port: 47312, dialog: false).slug
    assert_equal "listings_SOFA_7__markedsplass.brgen.no__1280__dialog.png",
                 TARGET.new(app: "brgen", host: "markedsplass.brgen.no", path: "/listings/SOFA-7", width: 1280, port: 47312, dialog: true).slug
    assert_equal "account__loopback__390.png",
                 TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: false).slug
  end

  def test_the_host_map_serves_each_pinned_host_from_its_own_app
    map = GoldenScreenshots.host_map([
      TARGET.new(app: "brgen", host: "dating.brgen.no", path: "/likes", width: 390, port: 38182, dialog: false),
      TARGET.new(app: "brgen", host: "tv.brgen.no", path: "/feed", width: 768, port: 38182, dialog: false),
      TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: false),
    ])

    assert_equal({ "dating.brgen.no" => "127.0.0.1:38182", "tv.brgen.no" => "127.0.0.1:38182" }, map)
  end

  # The manifest key is the walk's storage: a nil host serialises as an empty
  # field and reads back as nil, so a re-read target is the one the record
  # built - loopback authority, slug and baseline included.
  def test_a_row_key_round_trips_through_target_from
    keys.values.each do |key|
      original = GoldenScreenshots.target_from(key, "amber")
      reread = GoldenScreenshots.target_from(GoldenScreenshots.row_key(original), "amber")

      assert_equal original, reread
    end
  end

  # A CDP timeout is retryable and a page cell takes exactly one retry; every
  # other failure is taken as recorded. One flaky cell must not cost the
  # walk its whole rerun, and one retry must not paper over a dead surface.
  def test_a_pages_timeout_cell_retries_once_but_other_errors_do_not
    log = []
    fake = Class.new do
      def initialize(log) = (@log = log; @navs = Hash.new(0))

      %i[on_new_document emulate_reduced_motion viewport headers clear_cookies clear_events evaluate].each do |m|
        define_method(m) { |*| nil }
      end

      def navigate(url)
        @navs[url] += 1
        @log << "#{@navs[url]} #{url}"
        raise Deploy::CdpSession::Error, "CDP error" if url.include?("changelog")

        raise Deploy::CdpSession::Timeout, "navigate timeout" if url.include?("account") && @navs[url] == 1
      end

      def screenshot(path)
        @log << "shot"
        File.binwrite(path, WHITE.dup)
      end
    end.new(log)

    page = TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: false)
    other = TARGET.new(app: "amber", host: nil, path: "/changelog", width: 390, port: 61352, dialog: false)
    captured = nil
    Dir.mktmpdir("golden-retry") do |dir|
      original_open = Deploy::CdpSession.method(:open)
      Deploy::CdpSession.define_singleton_method(:open) { |*_args, &blk| blk&.call(fake) || fake }
      begin
        with_swap(:targets, ->(_app, _widths = nil) { [page, other] }) do
          captured = GoldenScreenshots.capture([page, other], dir: dir)
        end
      ensure
        Deploy::CdpSession.define_singleton_method(:open, original_open)
      end
    end

    assert_equal 2, log.count { |row| row =~ /\A\d http:\/\/127\.0\.0\.1:61352\/account\z/ }, "the timeout cell navigates once more"
    assert_equal 1, log.count { |row| row =~ /\A\d http:\/\/127\.0\.0\.1:61352\/changelog\z/ }, "a CDP error is taken as recorded, not retried"
    assert_equal Digest::SHA256.hexdigest(WHITE.dup), captured[page]
    assert_equal({ "error" => "Deploy::CdpSession::Error" }, captured[other])
  end

  # Autoplayed state is not a settled state: the session runs under emulated
  # reduced motion from the first cell on, so pages that honour it keep their
  # rotating state at the initial render instead of whichever step their
  # interval reached before the settle ended.
  def test_the_capture_emulates_reduced_motion_over_the_whole_session
    calls = []
    fake = Object.new
    %i[on_new_document viewport headers clear_cookies clear_events evaluate].each do |m|
      fake.define_singleton_method(m) { |*| nil }
    end
    fake.define_singleton_method(:emulate_reduced_motion) { calls << "reduce" }
    fake.define_singleton_method(:navigate) { |_url| nil }
    fake.define_singleton_method(:screenshot) { |path| File.binwrite(path, WHITE.dup) }

    page = TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: false)
    Dir.mktmpdir("golden-reduce") do |dir|
      original_open = Deploy::CdpSession.method(:open)
      Deploy::CdpSession.define_singleton_method(:open) { |*_args, &blk| blk&.call(fake) || fake }
      begin
        GoldenScreenshots.capture([page], dir: dir)
      ensure
        Deploy::CdpSession.define_singleton_method(:open, original_open)
      end
    end

    assert_equal 1, calls.count { |row| row == "reduce" }, "one emulation at session open covers every cell"
  end

  def record_test(targets, captures)
    with_swap(:targets, ->(_app, _widths = nil) { targets }) do
      with_swap(:manifest_path, ->(_app) { "/tmp/golden-test-record.golden.yml" }) do
        with_swap(:capture, ->(_targets, _dir: nil) { captures }) do
          rows = GoldenScreenshots.record("amber", [390])
          manifest = YAML.load_file("/tmp/golden-test-record.golden.yml")
          [rows, manifest]
        end
      end
    end
  ensure
    FileUtils.rm_f("/tmp/golden-test-record.golden.yml")
  end

  def test_a_record_writes_one_row_per_target_and_names_absent_dialog_states
    page = TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: false)
    dialog = TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: true)
    rows, manifest = record_test([page, dialog], { page => "sha1", dialog => nil })

    assert_equal "sha1", rows.fetch(GoldenScreenshots.row_key(page))
    assert_equal({ "present" => false }, rows.fetch(GoldenScreenshots.row_key(dialog)))
    assert_equal({ "schema" => 1, "app" => "amber", "widths" => [390], "rows" => rows }, manifest)
  end

  def test_a_recorded_dialog_capture_error_is_kept_but_a_page_one_fails_the_run
    page = TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: false)
    dialog = TARGET.new(app: "amber", host: nil, path: "/account", width: 390, port: 61352, dialog: true)
    rows, = record_test([page, dialog], { page => "sha1", dialog => { "error" => "CdpSession::Timeout" } })

    assert_equal({ "error" => "CdpSession::Timeout" }, rows.fetch(GoldenScreenshots.row_key(dialog)))

    error = assert_raises(SystemExit) do
      record_test([page], { page => { "error" => "CdpSession::Timeout" } })
    end

    assert_match(/failed to capture/, error.message, "a missing golden page is a loud abort, not a skip")
  end

  # An identical capture is no diff - and the sha is only believed after the
  # baseline file is proven to exist: a manifest row whose PNG vanished from
  # disk is a diff even when the next run would produce the same sha.
  def test_an_identical_capture_is_no_diff_but_a_vanishing_baseline_is_named
    assert_nil compare_row(manifest_rows: { keys[:loopback] => "sha1" },
                           key: keys[:loopback],
                           fresh: { GoldenScreenshots.target_from(keys[:loopback], "amber") => "sha1" },
                           with_baseline: true,
                           current: png(WHITE))
    assert_equal "no baseline file on disk",
                 compare_row(manifest_rows: { keys[:loopback] => "sha1" },
                             key: keys[:loopback],
                             fresh: { GoldenScreenshots.target_from(keys[:loopback], "amber") => "sha1" })
  end

  # Shas differ but pixels do not: the tolerance rule is the contract, not
  # byte equality, so an antialiasing-flavoured rerender does not name a row.
  def test_a_pixel_identical_rerender_with_a_different_sha_is_no_diff
    detail = compare_row(manifest_rows: { keys[:loopback] => "differentsha" },
                         key: keys[:loopback],
                         fresh: { GoldenScreenshots.target_from(keys[:loopback], "amber") => "freshsha" },
                         with_baseline: true,
                         current: png(WHITE))

    assert_nil detail
  end

  # Capture paths that never reach the tolerance rule are named, never skipped.
  def test_a_missing_baseline_and_a_failed_rerender_and_a_recorded_error_are_diffs
    target = GoldenScreenshots.target_from(keys[:loopback], "amber")

    assert_equal "no baseline file on disk",
                 compare_row(manifest_rows: { keys[:loopback] => "sha1" }, key: keys[:loopback], fresh: { target => "sha2" })
    assert_equal "capture failed: CdpSession::Timeout",
                 compare_row(manifest_rows: { keys[:loopback] => "sha1" }, key: keys[:loopback],
                             fresh: { target => { "error" => "CdpSession::Timeout" } })
    assert_equal "missing from the target",
                 compare_row(manifest_rows: { keys[:loopback] => "sha1" }, key: keys[:loopback], fresh: {})
    assert_equal "recorded capture errored: CdpSession::Timeout",
                 compare_row(manifest_rows: { keys[:loopback] => { "error" => "CdpSession::Timeout" } },
                             key: keys[:loopback], fresh: {})
  end

  def test_a_divergent_rerender_is_named_with_its_ratio
    detail = compare_row(manifest_rows: { keys[:loopback] => "goldensha" },
                         key: keys[:loopback],
                         fresh: { GoldenScreenshots.target_from(keys[:loopback], "amber") => "freshsha" },
                         with_baseline: true,
                         current: png(BLACK))

    assert_includes detail, "pixel ratio"
    assert_includes detail, GoldenScreenshots::TOLERANCE.to_s
  end

  def test_an_absent_dialog_state_stays_absent_and_is_never_re_captured
    with_swap(:manifest_path, ->(app) { "/tmp/golden-absent-#{app}.golden.yml" }) do
      File.write("/tmp/golden-absent-amber.golden.yml",
                 YAML.dump({ "schema" => 1, "app" => "amber", "widths" => [390], "rows" => { keys[:dialog] => { "present" => false } } }))
      asked = []
      with_swap(:capture, ->(targets, dir: nil) {
        asked.concat(targets)
        {}
      }) do
        diffs = GoldenScreenshots.check("amber", [390])
        FileUtils.rm_f("/tmp/golden-absent-amber.golden.yml")

        assert_empty diffs
        assert_empty asked, "an absent dialog cannot be re-captured, so the walk asks for nothing"
      end
    end
  end

  # The walk names its diffs and re-captures into its own tmp dir: the
  # recording directory is never the check's scratch space.
  def test_the_check_recaptures_into_a_tmp_dir
    with_swap(:manifest_path, ->(app) { "/tmp/golden-walk-#{app}.golden.yml" }) do
      File.write("/tmp/golden-walk-amber.golden.yml",
                 YAML.dump({ "schema" => 1, "app" => "amber", "widths" => [390], "rows" => { keys[:loopback] => "goldensha" } }))
      capture_dirs = []
      with_swap(:capture, ->(targets, dir:) {
        capture_dirs << [targets, dir]
        {}
      }) do
        diffs = GoldenScreenshots.check("amber", [390])
        FileUtils.rm_f("/tmp/golden-walk-amber.golden.yml")

        assert_equal ["|/account|390|page", "missing from the target"], diffs.first
        assert_equal 1, capture_dirs.size
        refute_equal GoldenScreenshots::DIR, capture_dirs.first[1], "the check's capture dir is a tmp dir"
        assert capture_dirs.first[1].start_with?(Dir.tmpdir)
        assert_equal [GoldenScreenshots.target_from(keys[:loopback], "amber")], capture_dirs.first[0],
                     "the present rows are re-captured; the absent state is not asked for"
      end
    end
  end
end
