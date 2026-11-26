#!/usr/bin/env ruby
# frozen_string_literal: true

# Boots every live apps.yml entry on the ports the checks probe: brgen,
# amber, bsdports, mrdamascy and the MASTER face. Inventory owns the fleet;
# this runner does not maintain a second list of app names.
#
#   bin/operator triangle up      boot, migrate, wait for /up, print status
#   bin/operator triangle up bsdports   the same, for the named surfaces only
#   bin/operator triangle status  which ports answer
#   bin/operator triangle down    stop only a verified checkout-owned process group
#
# Why this exists: the browser and live-HTTP checks need the same declared
# app processes as the deploy host. Brgen, Amber and BSDPorts have no bin/dev;
# this runner also brings up standalone Mr Damascy and the MASTER face from
# their actual deploy_root and port records.
#
# Pending migrations are the usual reason a booted app answers 500 rather than
# 200, so `up` migrates before it waits.

require "fileutils"
require "net/http"
require_relative "../../lib/io/exec"
require "yaml"
require_relative "../../lib/operator/ruby_runner"
require_relative "../../lib/fix/rails_app"
require_relative "../../lib/fix/server_leases"

module Deploy
  module Triangle
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    # Each app uses its own Gemfile and the interpreter selected by MASTER's
    # shared runtime policy. Never force an rbenv version from repository metadata.
    RUBY = Operator::RubyRunner.ruby_cmd
    BUNDLE = Operator::RubyRunner.bundle_cmd
    RUN_DIR = File.join(RAILS_ROOT, "tmp", "triangle")
    BOOT_TIMEOUT = Integer(ENV.fetch("TRIANGLE_BOOT_TIMEOUT", "180"))

    # Ports come from apps.yml so this file cannot disagree with the checks.
    def self.apps
      @apps ||= begin
        config = YAML.safe_load_file(File.join(RAILS_ROOT, "apps.yml")).fetch("apps")
        # The face is not a copy-tree app: apps.yml names its real directory in
        # deploy_root, and it is MASTER/web, not RAILS/master.
        config.map do |name, row|
          dir = File.join(ROOT, row.fetch("deploy_root", File.join("RAILS", name)))
          { name:, port: row.fetch("port"), dir:, rails: true }
        end
      end
    end

    # bin/operator runs under MASTER's own bundler environment, and a child `bundle exec`
    # inherits BUNDLE_GEMFILE from it: every app then booted on MASTER/Gemfile and died with
    # "cannot load bootsnap/setup" or "rails/commands". Each app is pinned to its own Gemfile
    # and the parent's bundler state is dropped, so the same command works from any caller.
    #
    # The BUNDLER_ORIG_* handles are the same leak by another door: a parent that ran
    # bundler/setup exports them, and the child's own bundler/setup restores GEM_HOME,
    # GEM_PATH and BUNDLE_PATH from them, overwriting the nils below with MASTER's paths.
    # An app then resolved its lockfile against MASTER's bundle and died on GemNotFound
    # naming gems MASTER never installs. Dropping the restore handles keeps the nils true.
    def self.env_for(app)
      env = Master::Fix::RailsApp::FOREIGN_BUNDLE.to_h { |key| [key, nil] }.merge(
        "RAILS_ENV" => "development", "PORT" => app[:port].to_s,
        "RAILS_LOG_LEVEL" => ENV.fetch("RAILS_LOG_LEVEL", "info"),
        "BUNDLE_GEMFILE" => File.join(app[:dir], "Gemfile"),
      )
      ENV.each_key { |key| env[key] = nil if key.start_with?("BUNDLER_ORIG_") }
      env
    end

    def self.listening?(port)
      response = Net::HTTP.start("127.0.0.1", port, open_timeout: 2, read_timeout: 4) { |http| http.get("/up") }
      response.code.to_i.between?(200, 399)
    rescue StandardError
      false
    end

    # The process listening on a port and the directory it was started in. lsof
    # is the only portable way to ask; nil when nothing listens or lsof cannot say.
    def self.listener(port)
      out, status = Master::Io::Exec.capture2e("lsof", "-nP", "-iTCP:#{port}", "-sTCP:LISTEN", "-Fp", timeout: 10)
      pid = status.success? ? out[/^p(\d+)/, 1] : nil
      return unless pid

      cwd_out, = Master::Io::Exec.capture2e("lsof", "-a", "-p", pid, "-d", "cwd", "-Fn", timeout: 10)
      { pid: pid.to_i, cwd: cwd_out[/^n(.+)$/, 1].to_s }
    rescue StandardError
      nil
    end

    # A server answering on the port is only this checkout's if it was started in
    # this checkout. One left behind by a sibling agent worktree (pub5-<name>)
    # answers /up too, so a booted run measured another tree's code. Those are
    # stopped; a server in the main checkout or anywhere else is the operator's
    # and is reported, never killed.
    SIBLING_WORKTREE = %r{/pub5-[^/]+/RAILS/}

    def self.foreign_listener(app)
      found = listener(app[:port])
      return if found.nil? || found[:cwd].start_with?(app[:dir])

      found
    end

    def self.reap_sibling(app, found)
      return false unless found[:cwd].match?(SIBLING_WORKTREE)

      pid = Integer(found[:pid])
      return false unless pid.positive?
      # Triangle boots each Rails process as a dedicated process-group leader.
      # A listener inside a sibling checkout is not enough authority to kill a
      # numeric PID; refuse if the group identity cannot be proved.
      return false unless Process.getpgid(pid) == pid

      warn "triangle: #{app[:name]} port #{app[:port]} was held by pid #{pid} from #{found[:cwd]}; stopping its owned process group"
      Master::Fix::ServerLeases.stop_process_group(pid)
    rescue StandardError => e
      warn "triangle: sibling server shutdown unconfirmed for pid #{found[:pid]} (#{e.class})"
      false
    end

    # An empty development database makes db:prepare run the seeds, which attach
    # images and took over ten minutes on a fresh /fix worktree. A seeded copy in
    # the main checkout is the same data, so a worktree starts from it.
    def self.seed_from_main(app)
      target = File.join(app[:dir], "storage")
      return if File.file?(File.join(target, "development.sqlite3"))

      common, status = Master::Io::Exec.capture2e("git", "-C", ROOT, "rev-parse", "--path-format=absolute", "--git-common-dir", timeout: 10)
      return unless status.success?

      source = File.join(File.dirname(common.strip), "RAILS", File.basename(app[:dir]), "storage")
      return if File.expand_path(source) == File.expand_path(target)
      return unless File.file?(File.join(source, "development.sqlite3"))

      FileUtils.mkdir_p(target)
      FileUtils.cp_r(File.join(source, "."), target)
      puts "triangle: #{app[:name]} database copied from #{source}"
    rescue StandardError => e
      warn "triangle: #{app[:name]} seeded database not copied (#{e.message}); db:prepare will seed"
    end

    def self.pid_file(app) = File.join(RUN_DIR, "#{app[:name]}.pid")

    # Rails otherwise shares tmp/pids/server.pid with a developer's server in
    # the same checkout. A Triangle capture on another port then waits for a
    # server Rails already refused to start.
    def self.rails_pid_file(app) = File.join(RUN_DIR, "#{app[:name]}.rails.pid")

    def self.log_file(app) = File.join(RUN_DIR, "#{app[:name]}.log")

    # application.css is built output and git-ignored, so a fresh worktree has
    # none: every page of an app whose layout links it answered 500 and the
    # rendered checks screenshotted Rails' error page instead of the layout.
    def self.build_css(app)
      return true unless File.file?(File.join(app[:dir], "app", "assets", "stylesheets", "application.scss"))
      return true if File.file?(File.join(app[:dir], "app", "assets", "builds", "application.css"))

      out, status = Master::Io::Exec.capture2e(RUBY, File.join(ROOT, "MASTER", "tools", "rails", "build_all_css.rb"), "--app", app[:name], chdir: ROOT, timeout: BOOT_TIMEOUT)
      return true if status.success?

      warn "triangle: #{app[:name]} css build failed\n#{out.lines.last(8).join}"
      false
    end

    def self.migrate(app)
      puts "triangle: #{app[:name]} prepare"
      seed_from_main(app)
      return false unless build_css(app)

      out, status = Master::Io::Exec.capture2e(env_for(app), BUNDLE, "exec", RUBY, "bin/rails", "db:prepare", chdir: app[:dir], timeout: BOOT_TIMEOUT)
      return true if status.success?

      warn "triangle: #{app[:name]} db:prepare failed\n#{out.lines.last(8).join}"
      false
    end

    # Propshaft pins the digest it serves through public/assets/.manifest.json,
    # and Rails says so out loud when you precompile in development: "Rails will
    # not serve any changed assets until you delete public/assets/.manifest.json".
    # So a stylesheet edit plus dartsass:build changes the file on disk and
    # nothing that a browser — or a rendered check — actually reads. On 2026-08-24
    # that cost three edit/build/measure rounds against an unchanged number while
    # the fix was already compiled in.
    #
    # Clearing it here rather than documenting it: a manual step that only
    # matters after a CSS change, and whose absence produces a plausible wrong
    # measurement rather than an error, is a step that will be skipped.
    def self.clear_asset_manifest(app)
      manifest = File.join(app[:dir], "public", "assets", ".manifest.json")
      File.delete(manifest) if File.file?(manifest)
    end

    def self.boot(app)
      clear_asset_manifest(app)
      FileUtils.mkdir_p(RUN_DIR)
      puts "triangle: #{app[:name]} boot #{app[:port]}"
      # Truncated, not appended. What this log is for is "why did this boot
      # fail", which the current boot answers; keeping every prior one grew
      # brgen.log to 1.8 GB and filled the disk.
      log = File.open(log_file(app), "w")
      pid = Process.spawn(
        Master::Io::ProcessSpawn.environment(env_for(app)),
        BUNDLE, "exec", RUBY, "bin/rails", "server", "-p", app[:port].to_s, "-b", "127.0.0.1",
        "--pid", rails_pid_file(app),
        chdir: app[:dir], out: log, err: log, pgroup: true
      )
      Process.detach(pid)
      File.write(pid_file(app), pid)
      pid
    end

    def self.wait_for(app)
      puts "triangle: #{app[:name]} wait /up (#{BOOT_TIMEOUT}s)"
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_TIMEOUT
      until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        return true if listening?(app[:port])

        sleep 2
      end
      false
    end

    # Named surfaces only, when names are given. One app with a prepared
    # database boots in about a minute, where all four wait on brgen's
    # db:prepare, so a rendered check can measure one app cheaply.
    def self.selected(names)
      return apps if names.empty?

      unknown = names - apps.map { |app| app[:name] }
      abort "triangle: no surface named #{unknown.join(', ')}" unless unknown.empty?
      apps.select { |app| names.include?(app[:name]) }
    end

    def self.up(names = [], &progress)
      failed = []
      selected(names).each { |app| failed << app[:name] unless boot_one(app, progress:) }
      failed
    end

    def self.boot_one(app, progress:)
      report_stage(progress, app, "inspect")
      server = existing_server(app)
      return true if server == :already_running
      return false if server == :blocked
      return missing_app(app) unless File.directory?(app[:dir])

      report_stage(progress, app, "prepare")
      return false unless migrate(app)

      report_stage(progress, app, "boot")
      boot(app)
      report_stage(progress, app, "wait", timeout: BOOT_TIMEOUT)
      return ready(app, progress) if wait_for(app)

      report_stage(progress, app, "timeout", timeout: BOOT_TIMEOUT)
      warn "triangle: #{app[:name]} did not answer /up within #{BOOT_TIMEOUT}s - see #{log_file(app)}"
      false
    end

    def self.existing_server(app)
      return :none unless listening?(app[:port])

      foreign = foreign_listener(app)
      return already_running(app) unless foreign
      return :none if reap_sibling(app, foreign)

      warn "triangle: #{app[:name]} port #{app[:port]} held by pid #{foreign[:pid]} " \
           "from #{foreign[:cwd]}, not this checkout"
      :blocked
    end

    def self.already_running(app)
      puts "triangle: #{app[:name]} already up on #{app[:port]}"
      :already_running
    end

    def self.missing_app(app)
      warn "triangle: #{app[:name]} has no directory at #{app[:dir]}"
      false
    end

    def self.ready(app, progress)
      report_stage(progress, app, "ready")
      puts "triangle: #{app[:name]} up on #{app[:port]}"
      true
    end

    def self.report_stage(progress, app, stage, **detail)
      progress&.call(app: app[:name], stage:, port: app[:port], **detail)
    end

    def self.status
      apps.map do |app|
        up = listening?(app[:port])
        puts "triangle: #{app[:name].ljust(9)} #{app[:port]} #{up ? 'up' : 'down'}"
        up
      end
    end

    def self.down(names = [])
      failed = []
      selected(names).each do |app|
        path = pid_file(app)
        unless File.file?(path)
          # A server whose pid file is gone (the run was killed) still holds the
          # port. The listener must still belong to this app and be the leader
          # of its own process group before the group is safe to stop.
          mine = listener(app[:port])
          if mine && mine[:cwd].start_with?(app[:dir])
            begin
              owned_group = Process.getpgid(mine[:pid]) == mine[:pid]
            rescue SystemCallError
              owned_group = false
            end
            unless owned_group
              warn "triangle: #{app[:name]} listener pid #{mine[:pid]} is not a verified isolated process group; refusing to stop it"
              failed << app[:name]
              next
            end
            if Master::Fix::ServerLeases.stop_process_group(mine[:pid])
              puts "triangle: stopped #{app[:name]} (pid #{mine[:pid]}, no pid file)"
            else
              warn "triangle: #{app[:name]} process group #{mine[:pid]} is still present; no pid file was removed"
              failed << app[:name]
            end
          end
          next
        end

        pid = Integer(File.read(path).strip, 10, exception: false)
        unless pid&.positive?
          warn "triangle: #{app[:name]} has an invalid pid file at #{path}; refusing to signal it"
          failed << app[:name]
          next
        end

        if Master::Fix::ServerLeases.stop_process_group(pid)
          FileUtils.rm_f(path) if Integer(File.read(path).strip, 10, exception: false) == pid
          Master::Fix::ServerLeases.release_record(pid_path: path, pid:)
          puts "triangle: stopped #{app[:name]} (pid #{pid})"
        else
          warn "triangle: #{app[:name]} process group #{pid} is still present; pid and owner leases retained"
          failed << app[:name]
        end
      rescue SystemCallError, ArgumentError => e
        warn "triangle: could not stop #{app[:name]} (#{e.class}: #{e.message})"
        failed << app[:name]
      end
      failed
    end
  end
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  case ARGV[0]
  when nil, "up"
    failed = Deploy::Triangle.up(ARGV.drop(1))
    exit(failed.empty? ? 0 : 1)
  when "status"
    exit(Deploy::Triangle.status.all? ? 0 : 1)
  when "down"
    failed = Deploy::Triangle.down(ARGV.drop(1))
    exit(failed.empty? ? 0 : 1)
  else
    warn "usage: bin/operator triangle [up|status|down] [surface ...]"
    exit 2
  end
end
