#!/usr/bin/env ruby
# frozen_string_literal: true

# Golden screenshots: what each recorded route answers a real browser, locked
# as an approved PNG per route, host and width. pub5 Phase 0, third row.
#
#   ruby MASTER/tools/rails/golden_screenshots.rb record brgen [--widths 390,768,1280]
#   ruby MASTER/tools/rails/golden_screenshots.rb check  brgen
#
# The corpus is the route contract's own recorded rows: a route that answers
# 200 text/html is captured at each width; a 302 or 404 is a redirect or an
# error page, not a golden page, so it takes no PNG and no row. A page whose
# DOM opens a <dialog> or [popover] on load is captured twice - once closed,
# once with the openable surface shown - because the dialog open is a route
# state a rewrite must not lose, and it is recorded only where the route
# presents one.
#
# Screenshots are viewport-sized at a fixed canonical height, rendered through
# the same CDP session the geometry checks use: one browser for the run, the
# subdomain hosts mapped to the apps' ports, Math.random seeded per document,
# and the volatile selectors (clocks, prices, relative times) hidden so the
# check compares pixels rather than content that changes between runs.
#
# The check walks the same manifest, re-captures the same cells against the
# running app and names every row whose pixels differ beyond a small
# tolerance; a missing baseline or a capture that errors is a diff, never a
# skip.

require "fileutils"
require "digest"
require "net/http"
require "tmpdir"
require "uri"
require "yaml"
require_relative "../../checks/support/geometry_probe"
require_relative "../../checks/support/cdp_session"
require_relative "../../checks/support/png_diff"

module GoldenScreenshots
  ROOT = File.expand_path("../../..", __dir__)
  DIR = File.join(ROOT, "MASTER", "checks", "data", "route_screenshots")
  GEOMETRY = File.join(ROOT, "MASTER", "checks", "data", "geometry_surfaces.yml")
  WIDTHS = [390, 768, 1280].freeze
  CANONICAL_HEIGHT = 900
  # Byte-identical baselines are the goal; a few antialiasing-flavoured pixels
  # between font-cache states are not a design change, so the check allows a
  # small pixel ratio before it names a row.
  TOLERANCE = 0.002
  TIMEOUT = Integer(ENV.fetch("GOLDEN_SCREENSHOT_TIMEOUT", "40"))

  Target = Data.define(:app, :host, :path, :width, :port, :dialog) do
    def authority = host || "127.0.0.1:#{port}"
    def slug
      # The recorded path is already id-normalised by the route contract; the
      # rest is shell-safety, not uniqueness.
      "#{path.gsub(%r{[^/\w]}, "_").tr("/", "_").sub(/\A_+/, "")}__#{host || "loopback"}__#{width}#{dialog ? "__dialog" : ""}.png"
    end
    def id = [@app, host, path, width, dialog ? "dialog" : "page"].join(" ")
  end

  module_function

  def contract_path(app) = File.join(ROOT, "MASTER", "checks", "data", "route_contracts", "#{app}.yml")

  def manifest_path(app) = File.join(DIR, "#{app}.golden.yml")

  def baseline_path(target) = File.join(DIR, target.app, target.slug)

  # The rows are read from the recorded contract, not from the manifest, so a
  # corpus captured in pub4 re-records against pub5's own routes: the golden
  # file names what was captured, nothing more.
  def targets(app, widths = WIDTHS, _root = ROOT)
    contract = YAML.load_file(contract_path(app))
    abort "golden_screenshots: no route contract for #{app}" unless contract.is_a?(Hash) && contract.key?("routes")

    ports = Deploy::GeometryProbe.app_ports(root: ROOT)
    width_list = Array(widths)
    contract["routes"].flat_map do |path, row|
      next unless row["status"] == 200 && row["type"] == "text/html"

      host = row["host"]
      width_list.flat_map do |width|
        [Target.new(app:, host:, path:, width:, port: ports.fetch(app), dialog: false),
         Target.new(app:, host:, path:, width:, port: ports.fetch(app), dialog: true)]
      end
    end.compact
  end

  def host_map(targets, _ports = {})
    targets.select(&:host).each_with_object({}) { |target, map| map[target.host] ||= "127.0.0.1:#{target.port}" }
  end

  # One browser, every cell. Each cell: fixed viewport, one navigation, the
  # volatile selectors hidden, then the screenshot; the dialog half asks the
  # openable surface to show itself and captures again. A page half that
  # cannot capture fails the run loudly; a dialog half with no dialog on the
  # page records an absent row instead - both are stated in the manifest.
  # The host map is this corpus's own: the run's contracts may pin hosts the
  # declared geometry inventory does not name.
  def capture(targets, dir: DIR)
    map = host_map(targets)
    captured = {}
    warm(targets)

    # TIMEOUT is wired here, not just declared: a corpus this big needs its
    # own ceiling (GOLDEN_SCREENSHOT_TIMEOUT), or the session quietly falls
    # back to CHECK_BROWSER_TIMEOUT's 20s and every slow page becomes a
    # capture failure that no recorder retry can redeem.
    Deploy::CdpSession.open(host_map: map, timeout: TIMEOUT) do |cdp|
      cdp.on_new_document(Deploy::GeometryProbe::DETERMINISM)
      targets.each do |target|
        state = capture_cell(cdp, target, dir)
        # A CDP timeout is retryable by cdp_session's own contract, and one
        # flaky cell otherwise costs the whole walk a rerun: page rows get
        # exactly one more try. Dialog rows keep their error as a stated
        # state, so they are recorded once.
        state = capture_cell(cdp, target, dir) if !target.dialog && state.is_a?(Hash) && state["error"] == "Deploy::CdpSession::Timeout"
        captured[target] = state
      end
    end
    captured
  end

  # One cell, one try: navigate to the contract row's URL, mask the volatile
  # selectors, screenshot to the row's slug file. A dialog row answers nil
  # when the page's openable surface does not open (the caller records that
  # as the absent state); any failure comes back as the error state.
  def capture_cell(cdp, target, dir)
    cdp.viewport(target.width, CANONICAL_HEIGHT, mobile: target.width < 500)
    cdp.headers(Deploy::GeometryProbe::PROBE_HEADERS)
    cdp.clear_cookies
    cdp.clear_events
    cdp.navigate("http://#{target.authority}#{target.path}")
    cdp.evaluate(mask_script)
    return nil if target.dialog && !open_dialog(cdp)

    path = File.join(dir, target.app.to_s, target.slug)
    FileUtils.mkdir_p(File.dirname(path))
    cdp.screenshot(path)
    Digest::SHA256.file(path).hexdigest
  rescue Deploy::CdpSession::Timeout, Deploy::CdpSession::Error, SystemCallError => e
    { "error" => e.class.name }
  end

  # One plain GET per distinct page before the browser opens: development-mode
  # Rails compiles a surface on first hit, and the browser's own budget is
  # nowhere near a cold compile. The walk's errors are already the contract's
  # business; warmup only costs what it can reach.
  def warm(targets)
    seen = {}
    targets.uniq { |t| [t.authority, t.path] }.each_with_object(seen) do |target, acc|
      url = "http://#{target.authority}#{target.path}"
      next if acc[url]

      acc[url] = true
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: 60) { |http| http.get(uri) }
    rescue StandardError
      next
    end
  end

  def mask_script
    selectors = YAML.safe_load_file(GEOMETRY)["volatile_selectors"]
    rule = selectors.join(", ") + " { visibility: hidden !important; }"
    "const s = document.createElement('style'); s.textContent = #{JSON.generate(rule)}; document.head.appendChild(s);"
  end

  # Open the page's own openable surface for the dialog state. showDialog is
  # script-callable without a user gesture; a popover the same. Only one per
  # page: the state is "an openable dialog shown", not every dialog at once.
  def open_dialog(cdp)
    answer = cdp.evaluate(<<~JS)
      (() => {
        const dialog = document.querySelector("dialog:not([open])");
        if (dialog) { dialog.showModal?.(); return dialog.checkVisibility?.() ? "dialog" : null; }
        const popover = document.querySelector("[popover]:not([open])");
        if (popover) { popover.showPopover?.(); return popover.checkVisibility?.() ? "popover" : null; }
        return null;
      })()
    JS
    !answer.nil?
  end

  def record(app, widths = WIDTHS)
    targets = targets(app, widths)
    captures = capture(targets)
    rows = {}
    failed = []
    targets.each do |target|
      sha = captures[target]
      if target.dialog
        state = if sha.is_a?(String)
                  sha
                elsif sha.is_a?(Hash) && sha["error"]
                  sha
                else
                  { "present" => false }
                end
        next rows[row_key(target)] = state
      end

      next failed << [target, sha["error"]] if sha.is_a?(Hash)
      rows[row_key(target)] = sha
    end
    # The walk runs to the end before it refuses, so one slow surface does not
    # throw away two-thirds of a capture, and no manifest is written for a
    # corpus that did not record whole.
    unless failed.empty?
      abort "golden_screenshots: #{failed.size} page(s) failed to capture:\n" +
            failed.map { |target, error| "  #{target.id}: #{error}" }.join("\n")
    end
    contract = { "schema" => 1, "app" => app, "widths" => Array(widths), "rows" => rows }
    File.write(manifest_path(app), YAML.dump(contract))
    pages = rows.keys.count { |key| key.end_with?("|page") }
    dialogs = rows.keys.count { |key| key.end_with?("|dialog") && rows[key].is_a?(String) }
    puts "#{app}: #{pages} golden pages, #{dialogs} dialog states recorded"
    puts "wrote #{manifest_path(app).delete_prefix("#{ROOT}/")}"
    rows
  end

  def row_key(target)
    [target.host, target.path, target.width, target.dialog ? "dialog" : "page"].join("|")
  end

  def check(app, widths = WIDTHS)
    capture_dir = nil
    manifest = YAML.load_file(manifest_path(app))
    abort "golden_screenshots: no golden manifest for #{app}" unless manifest.is_a?(Hash) && manifest.key?("rows")

    wanted = manifest["rows"]
    wanted_keys = wanted.keys.select { |key| widths.include?(key.split("|")[2].to_i) }
    present = wanted_keys.filter_map do |key|
      record = wanted[key]
      next if record.is_a?(Hash) # an absent dialog state cannot be re-captured

      target_from(key, app)
    end
    capture_dir = Dir.mktmpdir("golden-capture")
    fresh = capture(present, dir: capture_dir)

    diffs = wanted_keys.sort.filter_map do |key|
      detail = compare_row(manifest, key, app, fresh, capture_dir)
      next if detail.nil?

      [key, detail]
    end
    diffs.each { |key, detail| puts "#{key}  #{detail}" }
    puts "#{app}: #{diffs.empty? ? 'every golden screenshot matches' : "#{diffs.size} golden row(s) differ"}"
    diffs
  ensure
    FileUtils.remove_entry_secure(capture_dir) if capture_dir && Dir.exist?(capture_dir)
  end

  # A nil host serialises as an empty first field and reads back as nil, so a
  # re-read target is the target the record built - loopback authority, slug
  # and baseline included.
  def target_from(key, app)
    host, path, width, state = key.split("|")
    host = nil if host.to_s.empty?
    width = Integer(width, exception: false)
    return if width.nil? || path.nil?

    Target.new(app:, host:, path:, width:, port: Deploy::GeometryProbe.app_ports(root: ROOT).fetch(app), dialog: state == "dialog")
  end

  def compare_row(manifest, key, app, fresh, capture_dir)
    record = manifest["rows"][key]
    target = target_from(key, app)
    return "recorded capture errored: #{record["error"]}" if record.is_a?(Hash) && record.key?("error")
    return nil if record.is_a?(Hash) # recorded absent, stays absent

    fresh_sha = fresh[target]
    return "capture failed: #{fresh_sha["error"]}" if fresh_sha.is_a?(Hash)
    return "missing from the target" if fresh_sha.nil?

    baseline = baseline_path(target)
    return "no baseline file on disk" unless File.file?(baseline)

    current = File.join(capture_dir, target.app.to_s, target.slug)
    return "no capture file on disk" unless File.file?(current)

    return nil if fresh_sha == record

    ratio = Deploy::PngDiff.compare(baseline_path: baseline, current_path: current).dig(:pixel_diff_ratio)
    return "pixel ratio #{Float(ratio)} > #{TOLERANCE}" unless ratio && ratio <= TOLERANCE

    nil
  end
end

if $PROGRAM_NAME == __FILE__
  mode, app = ARGV.first(2)
  widths_flag_index = ARGV.index("--widths")
  widths = widths_flag_index ? ARGV[widths_flag_index + 1].split(",").map { |w| Integer(w) } : GoldenScreenshots::WIDTHS
  usage = "usage: golden_screenshots.rb record|check APP [--widths 390,768,1280]"
  abort usage unless %w[record check].include?(mode) && app

  result = mode == "record" ? GoldenScreenshots.record(app, widths) : GoldenScreenshots.check(app, widths)
  exit(mode == "check" && result.any? ? 1 : 0)
end
