# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "rbconfig"
require "socket"
require "yaml"
require_relative "../fix/routes_manifest"
require_relative "../io/exec"
require_relative "../io/ssrf_guard"
require_relative "ruby_runner"
require_relative "../../../OPENBSD/lib/deploy_inventory"

module Operator
  # The post-deploy canary. It answers one question after vps-deploy: is the box
  # serving what it should, and if not, exactly what is not.
  #
  #   ports      amber's and bsdports' ports are the ones a deploy sheds and
  #              relayd keeps answering TLS without, so a dead app looks like a
  #              hang; brgen and master are checked with them.
  #   services   rcctl check for each daemon.
  #   routes     every public GET route from the route manifest: 200..399, under
  #              the latency budget, response headers under relayd's 8 KB limit,
  #              no "translation missing" in the body.
  #   flows      the HTTP-only user journeys in checks/data/flows.yml (local mode only:
  #              they read the apps on 127.0.0.1), one result per journey.
  #   smoke      OPENBSD/bin/deploy-smoke.sh, the rehearsal subset that needs only
  #              the box itself.
  #
  # It reads and reports. Rolling back is a human decision, so on failure it
  # prints the previous deployed SHA and the commands, and runs none of them.
  module Canary
    HEADER_LIMIT_BYTES = 8 * 1024
    DEFAULT_BUDGET_MS = 3000
    SKIPPED_PREFIXES = %w[/internal /rails /cable /admin].freeze
    Reply = Struct.new(:status, :headers, :body, :elapsed_ms, keyword_init: true)
    Result = Struct.new(:name, :ok, :detail, :state, keyword_init: true)

    module_function

    def main(argv, root: File.expand_path("../../..", __dir__), out: $stdout, **runner_opts)
      opts = { mode: :local, apps: nil, budget_ms: DEFAULT_BUDGET_MS, smoke: true, flows: true, json: false }
      OptionParser.new do |o|
        o.on("--local") { opts[:mode] = :local }
        o.on("--public") { opts[:mode] = :public }
        o.on("--app LIST") { |v| opts[:apps] = v.split(",") }
        o.on("--budget-ms N", Integer) { |v| opts[:budget_ms] = v }
        o.on("--no-smoke") { opts[:smoke] = false }
        o.on("--no-flows") { opts[:flows] = false }
        o.on("--json") { opts[:json] = true }
      end.parse!(argv.dup)

      results = Runner.new(root:, **opts.slice(:mode, :apps, :budget_ms, :smoke, :flows), **runner_opts).run
      out.puts(opts[:json] ? JSON.pretty_generate(results.map(&:to_h)) : render(results, root))
      results.all?(&:ok) ? 0 : 1
    end

    def render(results, root)
      lines = results.map { |r| "#{r.state || (r.ok ? 'PASS' : 'FAIL')} #{r.name}#{r.detail.to_s.empty? ? '' : " - #{r.detail}"}" }
      failed = results.reject(&:ok)
      lines << (failed.empty? ? "canary: #{results.size} checks passed" : "canary: #{failed.size} of #{results.size} checks FAILED")
      lines.concat(Rollback.advice(root:)) unless failed.empty?
      lines.join("\n")
    end

    # What a failed canary tells the operator to do. It never does it.
    module Rollback
      module_function

      def advice(root:, git: ->(*argv) { Master::Io::Exec.capture2(*argv, err: File::NULL).first.to_s.strip })
        current = git.call("git", "-C", root, "rev-parse", "--short", "HEAD")
        [
          "",
          "rollback (manual; the canary changes nothing):",
          "  source checkout HEAD: #{current.empty? ? 'unknown' : current}",
          "  HEAD@{1} is not proof of the last known-good deployment and is deliberately not used.",
          "  Inspect /var/db/pub5/last_deploy_<app>.json and the matching deploy-run receipt",
          "  to identify the affected app's last known-good SHA before choosing a rollback.",
          "  Make a reviewed, app-scoped revert on main, push it, then redeploy that app:",
          "    bin/operator vps deploy <app> --remote",
          "  Do not infer a revert range from the local Git reflog.",
        ]
      end
    end

    class Runner
      def initialize(root:, mode: :local, apps: nil, budget_ms: DEFAULT_BUDGET_MS, smoke: true, flows: true,
                     http: nil, shell: nil, connect: nil)
        @root = root
        @mode = mode
        @budget_ms = budget_ms
        @smoke = smoke
        @flows = flows
        @http = http || method(:fetch)
        @shell = shell || ->(*argv) { Master::Io::Exec.capture2e(*argv) }
        @connect = connect || method(:open_port)
        @apps = load_apps(apps)
      end

      def run
        results = []
        results.concat(port_checks) if @mode == :local
        results.concat(service_checks) if @mode == :local
        results.concat(route_checks)
        results.concat(flow_checks) if @flows && @mode == :local
        results.concat(smoke_check) if @smoke
        results
      end

      private

      def load_apps(only)
        data = YAML.safe_load_file(File.join(@root, "RAILS", "apps.yml"), aliases: true).fetch("apps")
        apps = data.select { |_name, row| row["public"] && row["port"] && row["deployed"] != false }
                   .transform_values { |row| row.slice("domain", "port") }
        only ? apps.slice(*only) : apps
      end

      def port_checks
        @apps.map do |name, cfg|
          up = @connect.call("127.0.0.1", cfg["port"])
          Result.new(name: "port #{cfg['port']} (#{name})", ok: up, detail: up ? nil : "closed - the app is down or was shed; relayd still answers TLS")
        end
      end

      def service_checks
        services = (@apps.keys + ["relayd"]).uniq
        services.map do |svc|
          out, status = @shell.call("rcctl", "check", svc)
          Result.new(name: "rcctl #{svc}", ok: status.success?, detail: status.success? ? nil : out.to_s.strip.lines.last.to_s.strip)
        rescue SystemCallError => e
          Result.new(name: "rcctl #{svc}", ok: false, detail: "#{e.class}: #{e.message}")
        end
      end

      def route_checks
        @apps.flat_map do |name, cfg|
          paths = paths_for(name)
          paths.map { |path| route_result(name, cfg, path) }
        end
      end

      def paths_for(app)
        # master's routes are its own chat and face endpoints, most of them
        # streams or behind AuthTier, so its canary is liveness alone.
        return ["/up"] if app == "master"

        manifest = Master::Fix::RoutesManifest.new(app_root: File.join(@root, "RAILS", app), shared_root: File.join(@root, "RAILS", "__shared"))
        (["/up"] + manifest.public_get_paths).uniq.reject { |p| SKIPPED_PREFIXES.any? { |s| p.start_with?(s) } }
      end

      def route_result(app, cfg, path)
        reply = @http.call(@mode == :local ? "127.0.0.1" : cfg["domain"], @mode == :local ? cfg["port"] : 443, path, cfg["domain"], @mode == :public)
        problems = problems_for(reply)
        Result.new(name: "GET #{app} #{path}", ok: problems.empty?, detail: problems.empty? ? "#{reply.status} #{reply.elapsed_ms}ms" : problems.join("; "))
      rescue StandardError => e
        Result.new(name: "GET #{app} #{path}", ok: false, detail: "#{e.class}: #{e.message}")
      end

      def problems_for(reply)
        problems = []
        problems << "status #{reply.status}, expected 200..399" unless (200..399).cover?(reply.status)
        problems << "#{reply.elapsed_ms}ms over the #{@budget_ms}ms budget" if reply.elapsed_ms > @budget_ms
        size = header_bytes(reply.headers)
        problems << "response headers #{size} bytes, relayd's limit is #{HEADER_LIMIT_BYTES}" if size >= HEADER_LIMIT_BYTES
        problems << "body contains 'translation missing'" if reply.body.to_s.match?(/translation[ _]missing/i)
        problems
      end

      def header_bytes(headers)
        headers.sum { |k, vs| Array(vs).sum { |v| "#{k}: #{v}\r\n".bytesize } }
      end

      FLOW_LINE = %r{surface0: (?<app>[\w-]+)/(?<id>\S+) (?<state>PASS|FAIL|INCONCLUSIVE|SKIPPED|ERROR)\b}
      FLOW_PROBLEM = /^\s*- flow:(?<id>\S+?)[\s:\/](?<why>.*)$/

      # The flow_journey check, scoped to the apps under test, reported per journey.
      # A journey that could not run (no credentials, port closed) is not a failure
      # here: the port and rcctl checks own "down", and an unmeasured journey is
      # named as such rather than counted as passed.
      def flow_checks
        script = File.join(@root, "MASTER", "checks", "runner.rb")
        return [Result.new(name: "flows", ok: false, state: "FAIL", detail: "missing MASTER/checks/runner.rb")] unless File.file?(script)

        out, status = @shell.call("env", "CHECK_AUTOFIX=0", "FLOW_APP=#{@apps.keys.join(',')}", RbConfig.ruby, script, "flow_journey")
        rows = out.to_s.lines.filter_map { |line| FLOW_LINE.match(line) }
        if rows.empty?
          detail = out.to_s.lines.last(3).join.strip
          detail = "runner returned no flow results#{status.success? ? "" : " and exited unsuccessfully"}#{detail.empty? ? "" : ": #{detail}"}"
          return [Result.new(name: "flows", ok: false, state: "FAIL", detail:)]
        end

        problems = out.to_s.lines.filter_map { |line| FLOW_PROBLEM.match(line) }.to_h { |m| [m[:id], m[:why].strip] }
        results = rows.map do |m|
          bad = %w[FAIL ERROR].include?(m[:state])
          Result.new(name: "flow #{m[:app]}/#{m[:id]}", ok: !bad, state: m[:state], detail: bad ? (problems[m[:id]] || m[:state]) : m[:state].downcase)
        end
        if !status.success? && rows.none? { |m| %w[FAIL ERROR].include?(m[:state]) }
          results << Result.new(name: "flows process", ok: false, state: "FAIL", detail: "runner exited unsuccessfully: #{out.to_s.lines.last(3).join.strip}")
        end
        results
      rescue SystemCallError => e
        [Result.new(name: "flows", ok: false, detail: "#{e.class}: #{e.message}")]
      end

      def smoke_check
        script = File.join(@root, "OPENBSD", "bin", "deploy-smoke.sh")
        unless File.file?(script)
          return [Result.new(
            name: "deploy-smoke #{@mode}",
            ok: false,
            detail: "missing OPENBSD/bin/deploy-smoke.sh",
          )]
        end

        out, status = @shell.call("sh", script, @mode == :local ? "--local" : "--public")
        [Result.new(name: "deploy-smoke #{@mode}", ok: status.success?, detail: status.success? ? nil : out.to_s.lines.grep(/FAIL/).first(4).join(" ").strip)]
      rescue SystemCallError => e
        [Result.new(name: "deploy-smoke #{@mode}", ok: false, detail: "#{e.class}: #{e.message}")]
      end

      def open_port(host, port)
        Socket.tcp(host, port, connect_timeout: 3) { true }
      rescue SystemCallError, Socket::ResolutionError
        false
      end

      # Net::HTTP without following redirects: a 3xx is the answer being judged.
      def fetch(host, port, path, domain, tls)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        headers = { "Host" => domain, "Accept-Language" => "nb", "User-Agent" => "pub5-canary" }
        request = Net::HTTP::Get.new(path, headers)
        res = if tls
                uri = URI::HTTPS.build(host: domain, port:, path:)
                raise URI::InvalidURIError, "public canary requires HTTPS on port 443" unless port == 443

                Master::Io::SsrfGuard.request(uri, request, max_bytes: 2_000_000, timeout: 15)
              else
                # Local mode deliberately addresses the loopback service by its
                # configured port; it is not an untrusted public URL fetch.
                http = Net::HTTP.new(host, port, nil)
                http.open_timeout = http.read_timeout = 15
                http.write_timeout = 15
                http.start { |connection| connection.request(request) }
              end
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        Reply.new(status: res.code.to_i, headers: res.to_hash, body: res.body.to_s, elapsed_ms: ms)
      end
    end
  end

  # The checks the code about to be deployed must pass before anything on vm23
  # is stopped. A SyntaxError or a law that raises at boot kills master's
  # container after production is already shed, so each check below reproduces
  # such a failure where it is cheap: before the deploy, not after the stop.
  #
  #   syntax       every Ruby file under MASTER/lib, MASTER/law and RAILS/*/app
  #                compiles (one process, no per-file ruby -c)
  #   law files    MASTER/test/test_law_files_load.rb, each law file in its own process
  #   boot smoke   MASTER/tools/boot_smoke.rb, which builds the FixLoop
  #   rehearse     OPENBSD/bin/rehearse, the static deploy contracts (the Mac only:
  #                it loads RAILS tests the box has no reason to carry)
  module DeployPreflight
    Result = Struct.new(:name, :ok, :detail, keyword_init: true)

    class GitCommandError < StandardError; end

    SWEEP_GLOBS = %w[MASTER/lib/**/*.rb MASTER/law/**/*.rb RAILS/*/app/**/*.rb STUDIO/**/*.rb].freeze
    TIMEOUT = 900
    # A single-app Rails suite may take close to an hour on a one-core host.
    # Keep the whole child process group under a real deadline.
    LOCAL_CI_TIMEOUT = 3_600

    module_function

    def main(argv, root: File.expand_path("../../..", __dir__), out: $stdout)
      opts = { rehearse: true }
      OptionParser.new do |o|
        o.on("--root DIR") { |v| root = v }
        o.on("--no-rehearse") { opts[:rehearse] = false }
      end.parse!(argv.dup)
      results = run(root:, **opts)
      out.puts(report(results))
      results.all?(&:ok) ? 0 : 1
    end

    # Stops at the first failure: the later checks load the same code, and the
    # first message is the one the operator needs.
    def run(root:, rehearse: true, studio: false, runner: method(:capture))
      results = []
      steps(root, rehearse, studio, runner).each do |name, step|
        results << step.call
        results.last.name = name
        break unless results.last.ok
      end
      results
    end

    def steps(root, rehearse, studio, runner)
      ruby = RbConfig.ruby
      list = {
        "syntax" => -> { syntax(root) },
        "law files" => -> { shell(runner, [ruby, "-Itest", "test/test_law_files_load.rb"], File.join(root, "MASTER")) },
        "boot smoke" => -> { shell(runner, [ruby, "tools/boot_smoke.rb"], File.join(root, "MASTER")) },
      }
      list["rehearse"] = -> { shell(runner, [ruby, "OPENBSD/bin/rehearse"], root) } if rehearse
      if studio
        list["STUDIO check + test"] = lambda {
          shell(runner, [ruby, "-S", "rake", "-f", "replicate/Rakefile", "check", "test"], File.join(root, "STUDIO"))
        }
      end
      list
    end

    def syntax(root)
      bad = SWEEP_GLOBS.flat_map { |glob| Dir.glob(File.join(root, glob)) }.sort.filter_map do |file|
        RubyVM::InstructionSequence.compile_file(file)
        nil
      rescue SyntaxError => e
        "#{file.delete_prefix("#{root}/")}: #{e.message.lines.first.to_s.strip}"
      end
      Result.new(ok: bad.empty?, detail: bad.first(5).join("\n"))
    end

    MAX_FAILURE_DETAIL_BYTES = 32_768

    def shell(runner, argv, chdir)
      out, ok = runner.call(argv, chdir)
      Result.new(ok:, detail: ok ? "" : bounded_failure_detail(out))
    end

    # Keep the failure heading and its final context together. Taking only the
    # last lines hid Minitest's failing test name when the rehearsal continued
    # with later green checks, leaving operators with "Actual: 0" and no cause.
    def bounded_failure_detail(output)
      text = output.to_s
      return text if text.bytesize <= MAX_FAILURE_DETAIL_BYTES

      half = (MAX_FAILURE_DETAIL_BYTES - 80) / 2
      head = text.byteslice(0, half).to_s.scrub
      tail = text.byteslice(-half, half).to_s.scrub
      "#{head}\n... failure output truncated; omitted #{text.bytesize - head.bytesize - tail.bytesize} bytes ...\n#{tail}"
    end

    def capture(argv, chdir, timeout: TIMEOUT)
      out, status = Master::Io::Exec.capture2e(*argv, chdir:, timeout:, raise_on_timeout: true)
      [out, status.success?]
    rescue Master::Io::Exec::TimeoutError => error
      out = Array(error.result).first.to_s
      out << "\n" unless out.empty? || out.end_with?("\n")
      [out + "timed out after #{timeout}s\n", false]
    end

    # `bin/operator vps deploy <app> --remote`: judge the commit here, then hand the
    # box the exact SHA and the word that it passed. Returns [true, command] or
    # [false, reason]; the caller runs the command or prints the reason.
    #
    # The commit judged is HEAD, and HEAD must be origin/main with no edits to
    # tracked files in the governed trees, because the box deploys origin/main and a
    # preflight of anything else proves nothing about what it will run.
    #
    # Every Rails app selected by the target runs bin/ci here, serially, before
    # SSH. Group and all targets are included: no child deploy can run its suite
    # on vm23.
    def remote_command(root:, app:, env: ENV, git: method(:git_out), runner: method(:capture), out: $stdout,
                       ci_runner: method(:local_ci))
      inventory = Deploy::Inventory.new(root:)
      return [false, "unknown deployment target #{app.inspect}; no inventory match"] if inventory.target_kind(app) == :unknown

      git.call(root, "fetch", "-q", "origin", "main")
      sha = git.call(root, "rev-parse", "HEAD")
      return [false, "cannot read HEAD of #{root}"] if sha.empty?
      return [false, "HEAD #{sha[0, 9]} is not origin/main (#{git.call(root, 'rev-parse', 'origin/main')[0, 9]}); the box deploys origin/main, so push and deploy from that commit"] unless git.call(root, "rev-parse", "origin/main") == sha

      dirty = git.call(root, "status", "--porcelain", "--untracked-files=normal", "--", "MASTER", "RAILS", "OPENBSD", "STUDIO")
      return [false, "commit these first; remove untracked files that are not part of the release:\n#{dirty.lines.first(5).join}"] unless dirty.empty?

      lead = "cd /home/dev/pub5 && VPS_DEPLOY_SHA=#{sha}"
      tail = "zsh OPENBSD/bin/vps-deploy #{app}"
      preflight_word = nil
      if env["VPS_DEPLOY_SKIP_PREFLIGHT"] == "1"
        return [false, "VPS_DEPLOY_SKIP_PREFLIGHT=1 needs the human-only I_UNDERSTAND_FAST_DEPLOY=1"] unless env["I_UNDERSTAND_FAST_DEPLOY"] == "1"

        preflight_word = "VPS_DEPLOY_SKIP_PREFLIGHT=1 I_UNDERSTAND_FAST_DEPLOY=1"
      else
        results = run(root:, runner:, studio: inventory.target_kind(app) == :all)
        out.puts(report(results))
        return [false, "preflight failed on #{sha[0, 9]}; nothing was sent to the box"] unless results.all?(&:ok)

        preflight_word = "VPS_DEPLOY_PREFLIGHT_SHA=#{sha}"
      end

      run_ci = lambda do |ci_app|
        out.puts("ci0: #{ci_app} bin/ci on #{sha[0, 9]} here; vm23 will only verify the installed bundle")
        ci_runner.call(root:, app: ci_app)
      end
      ok, ci_word = ci_attestation(root:, target: app, sha:, run: run_ci)
      return [false, ci_word] unless ok

      [true, [lead, preflight_word, ci_word, tail].compact.join(" ")]
    rescue GitCommandError => error
      [false, "repository preflight failed: #{error.message}; nothing was sent to vm23"]
    end

    # CI scope follows the canonical inventory. A batch runs each selected Rails
    # app locally in deploy order; MASTER remains covered by the local preflight.
    def ci_attestation(root:, target:, sha:, run:)
      inventory = Deploy::Inventory.new(root:)
      rows = case inventory.target_kind(target)
             when :app
               inventory.apps.select { |candidate| candidate.name == target }
             when :group
               inventory.ordered_apps(group: target)
             when :all
               inventory.ordered_apps
             else
               []
             end
      rails_apps = rows.select { |candidate| candidate.deploy_group == "rails" }
      rails_apps.each do |candidate|
        next if run.call(candidate.name)

        return [false, "#{candidate.name} bin/ci failed here on #{sha[0, 9]}; nothing was sent to the box"]
      end
      return [true, nil] if rails_apps.empty?

      [true, "VPS_DEPLOY_CI_SHA=#{sha}"]
    end

    # Run each app under the interpreter MASTER selected for this checkout;
    # clear the caller's Bundler state so the app activates its own Gemfile.
    def local_ci(root:, app:, out: $stdout, err: $stderr)
      dir = File.join(root, "RAILS", app)
      ruby = RubyRunner.ruby_cmd(root:)
      cleared = %w[BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH GEM_HOME GEM_PATH RUBYOPT RUBYLIB].to_h { [_1, nil] }
      env = cleared.merge("PATH" => "#{File.dirname(ruby)}:#{ENV.fetch("PATH", "")}", "PUB5_CI_APP" => app)
      output, status = Master::Io::Exec.capture2e(
        env, ruby, "bin/ci", chdir: dir, timeout: LOCAL_CI_TIMEOUT, raise_on_timeout: true
      )
      out.write(output) unless output.empty?
      status.success?
    rescue Master::Io::Exec::TimeoutError => error
      output = Array(error.result).first.to_s
      out.write(output) unless output.empty?
      err.puts("ci0: #{app} bin/ci timed out after #{LOCAL_CI_TIMEOUT}s")
      false
    end

    def git_out(root, *argv)
      output, status = Master::Io::Exec.capture2(
        "git", "-C", root, *argv, err: File::NULL,
        timeout: Master::Io::Exec::DEFAULT_TIMEOUT, raise_on_timeout: true
      )
      unless status.success?
        exit_code = status.exitstatus || "signal"
        raise GitCommandError, "git #{argv.join(" ")} failed (#{exit_code})"
      end

      output.to_s.strip
    rescue Master::Io::Exec::TimeoutError
      raise GitCommandError, "git #{argv.join(" ")} timed out after #{Master::Io::Exec::DEFAULT_TIMEOUT}s"
    rescue SystemCallError => error
      raise GitCommandError, "git #{argv.join(" ")} could not run (#{error.class}: #{error.message})"
    end

    def report(results)
      failed = results.find { |r| !r.ok }
      lines = results.map { |r| "#{r.ok ? 'ok  ' : 'FAIL'} preflight #{r.name}" }
      return (lines << "preflight: all #{results.size} checks passed").join("\n") unless failed

      lines << failed.detail.to_s.lines.map { |l| "       #{l.rstrip}" }.join("\n")
      lines << "preflight: #{failed.name} FAILED - deployment blocked during preflight. Nothing was stopped or pulled onto the box."
      lines.join("\n")
    end
  end
end

exit Operator::DeployPreflight.main(ARGV) if $PROGRAM_NAME == __FILE__
