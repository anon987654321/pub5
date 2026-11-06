# frozen_string_literal: true

# The one acceptance command. Runs every Phase 0 instrument a target can
# answer, and names every instrument it cannot - with the thing it is missing,
# not a skip that reads as a pass.
#
#   ruby MASTER/tools/acceptance.rb [--root PATH] [--base-url URL] [--user email:password]
#
# Root instruments (CLI contracts, Law proof fixtures) run against the tree;
# so do the round-trip suites, one rails boot per app. Route contracts run
# only against a booted base URL: without one they are named, never claimed.
# The golden screenshot half costs a full Chrome re-capture of every recorded
# manifest, so --screenshots asks for it; unrecorded or unasked-for halves
# answer as what is left to do, never a skip that reads as a pass.

require "open3"

module Acceptance
  ROOT = File.expand_path("../..", __dir__)
  TOOLS = File.dirname(__FILE__)

  Report = Data.define(:name, :state, :detail) do
    def failed = state == "fail"
    def pending? = state == "pending"
  end

  module_function

  def main(argv = ARGV)
    flags = ->(name) { argv.include?(name) ? argv[argv.index(name) + 1] : nil }
    root = flags.call("--root") || ROOT
    base = flags.call("--base-url")
    user = flags.call("--user")

    reports = [root_contracts(root), round_trips(root), route_contracts(base), signed_contracts(base, user),
               golden_screenshots(screenshots: argv.include?("--screenshots"))]
    reports.each do |report|
      puts format("%-24s %s", report.name, report.failed ? "fail: #{report.detail}" : report.state)
    end
    reports.select(&:pending?).each { |report| puts format("%-24s pending: %s", report.name, report.detail) }
    puts "#{reports.select(&:pending?).size} still unrecorded, #{reports.select(&:failed).size} failed"
    reports.select(&:failed).empty? ? 0 : 1
  end

  # One spawn seam each, so the tests can answer for the subprocesses; the
  # live anchor runs them for real.
  def spawn_tool(script, args) = Open3.capture3(RbConfig.ruby, script, *args)
  def spawn_app(dir) = Open3.capture3(*app_rails(dir), "test", "test/account_round_trip_test.rb", chdir: dir)
  def spawn_route(*args) = Open3.capture3(RbConfig.ruby, File.join(TOOLS, "rails", "route_contracts.rb"), *args)

  # Each checkable instrument answers pass or fail; the detail is the
  # instrument's own last words, not an interpretation of them.
  def root_contracts(root)
    fails = [
      ["cli contracts", File.join(TOOLS, "cli_contracts.rb"), ["check", "--root", root]],
      ["law proof fixtures", File.join(TOOLS, "law_fixtures.rb"), ["check", "--root", root]],
    ].filter_map do |name, script, args|
      out, err, status = spawn_tool(script, args)
      "#{name}: #{(out + err).lines.last(2).join.strip}" unless status.success?
    end
    Report.new(*[("root contracts"), fails.empty? ? "pass" : "fail", fails.empty? ? "" : fails.join("\n")])
  end

  # One rails boot per app that ships the round-trip suite; whatever its
  # test helper and bundler answer decides the verdict. A tree without app
  # dirs answers pending, as pub5 today does.
  def round_trips(root)
    app_roots = %w[brgen amber bsdports].map { |app| File.join(root, "RAILS", app) }
    booted = app_roots.select { |dir| File.file?(File.join(dir, "bin", "rails")) }
    return Report.new("export/import round-trip", "pending", "no app trees under #{root}") if booted.empty?

    fails = booted.filter_map do |dir|
      app = File.basename(dir)
      out, err, status = spawn_app(dir)
      next if status.success?

      detail = (out + err).lines.last(3).join.strip
      "#{app}: #{detail}"
    end
    Report.new("export/import round-trip", fails.empty? ? "pass" : "fail", fails.empty? ? "" : fails.join("\n"))
  end

  # The documented operator invocation: this Mac's profile never puts rbenv
  # shims on PATH, so a tree whose .ruby-version names a rbenv-installed
  # version runs through `rbenv exec`; a host with a native ruby runs
  # bin/rails as itself.
  def app_rails(dir)
    if system("rbenv --version", out: File::NULL, err: File::NULL) &&
       File.file?(File.join(dir, ".ruby-version"))
      ["rbenv", "exec", "ruby", "bin/rails"]
    else
      ["bin/rails"]
    end
  end

  def route_contracts(base)
    return Report.new("route contracts", "pending", "needs --base-url (a booted target)") unless base

    # The instrument's own report names every diff; a non-zero exit anywhere
    # is this command's failure, with the instrument's last lines as detail.
    detail = recorded_apps(".yml").filter_map do |app|
      out, _err, status = spawn_route("check", app, base)
      "(#{app}) #{out.lines.last(1).join.strip}" unless status.success?
    end
    Report.new("route contracts", detail.empty? ? "pass" : "fail", detail.join("\n"))
  end

  def signed_contracts(base, user)
    unless base && user && signed_apps.any?
      missing = signed_apps.any? ? "checks need --base-url and --user email:password" : "no signed half recorded yet"
      return Report.new("signed route contracts", "pending", missing)
    end

    detail = signed_apps.filter_map do |app|
      out, _err, status = spawn_route("check-signed", app, base, "--user", user)
      "(#{app}) #{out.lines.last(1).join.strip}" unless status.success?
    end
    Report.new("signed route contracts", detail.empty? ? "pass" : "fail", detail.join("\n"))
  end

  def recorded_apps(suffix)
    # match? leaves $~ untouched by design, so a capturing slice names the app.
    Dir.children(File.join(ROOT, "MASTER", "checks", "data", "route_contracts"))
       .filter_map { |file| file[/\A(\w+)#{Regexp.escape(suffix)}\z/, 1] }
  end

  def signed_apps = recorded_apps(".signed.yml")

  # The screenshot half re-captures every recorded manifest row against the
  # booted app ports through Chrome, at a cost of tens of minutes for the
  # whole corpus - so --screenshots asks for it explicitly. A manifest that
  # no longer verifies fails with the instrument's own named diffs; pending
  # is what an unrecorded or unasked-for half answers, never a pass.
  def golden_screenshots(screenshots: false)
    recorded = golden_apps
    return Report.new("golden screenshots", "pending", "no manifest recorded yet (golden_screenshots.rb record APP)") if recorded.empty?

    return Report.new("golden screenshots", "pending",
                      "re-run with --screenshots to re-capture #{recorded.join(', ')}" \
                      " (needs Chrome and the recorded app ports booted)") unless screenshots

    detail = recorded.filter_map do |app|
      out, err, status = spawn_screenshot("check", app)
      "(#{app}) #{(out + err).lines.last(2).join.strip}" unless status.success?
    end
    Report.new("golden screenshots", detail.empty? ? "pass" : "fail", detail.join("\n"))
  end

  def spawn_screenshot(*args) = Open3.capture3(RbConfig.ruby, File.join(TOOLS, "rails", "golden_screenshots.rb"), *args)

  # The recorded screenshot half, named from its own data dir.
  def golden_apps
    dir = File.join(ROOT, "MASTER", "checks", "data", "route_screenshots")
    return [] unless Dir.exist?(dir)

    Dir.children(dir).filter_map { |f| f[/\A(\w+)\.golden\.yml\z/, 1] }.sort
  end
end

if $PROGRAM_NAME == __FILE__
  exit(Acceptance.main)
end
