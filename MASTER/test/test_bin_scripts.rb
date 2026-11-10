# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
require "yaml"

# The lifecycle scripts in bin/, run as processes. Each script resolves its
# paths from its own location, so a copy under a temporary MASTER/ directory
# writes into that directory and never into the checkout.
class TestBinScripts < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_doctor_reports_ok_fail_lines
    output, = Open3.capture3({ "MASTER_KEYLESS" => "1" }, RbConfig.ruby, File.join(ROOT, "bin", "doctor"), chdir: ROOT)

    assert_includes output, "MASTER doctor"
    assert_match(/^doctor\d+ at doctor0: yaml, (?:ok|fail)$/, output)
    assert_match(/^doctor\d+ at doctor0: (?:ruby|git), ok$/, output)
    refute_includes output, "[\"receipt:", "the boot receipt prints as lines, not an array"
  end

  def test_cleanup_refuses_a_dirty_tree
    Dir.mktmpdir do |repo|
      script = cleanup_fixture(repo)
      File.write(File.join(repo, "untracked.txt"), "x")

      out, status = Open3.capture2e(RbConfig.ruby, script, chdir: repo)

      refute status.success?
      assert_includes out, "working tree dirty"
    end
  end

  def test_cleanup_is_a_dry_run_by_default_and_writes_its_reports
    Dir.mktmpdir do |repo|
      script = cleanup_fixture(repo)

      out, status = Open3.capture2e(RbConfig.ruby, script, chdir: repo)

      assert status.success?, out
      assert_includes out, "test_shot.jpg"
      assert File.exist?(File.join(repo, "test_shot.jpg")), "a dry run deleted a candidate"
      reports = Dir.children(File.join(repo, "MASTER", "reports", "cleanup"))
      assert(reports.any? { |name| name.start_with?("inventory_before.json") })
      assert(reports.any? { |name| name.start_with?("history_before.txt") })
    end
  end

  def test_cleanup_apply_removes_the_candidates
    Dir.mktmpdir do |repo|
      script = cleanup_fixture(repo)

      out, status = Open3.capture2e(RbConfig.ruby, script, "--apply", chdir: repo)

      assert status.success?, out
      refute File.exist?(File.join(repo, "test_shot.jpg"))
    end
  end

  def test_smoke_pipe_command_uses_the_bounded_executor
    source = File.read(File.join(ROOT, "bin", "smoke"))

    assert_includes source, "Master::Io::Exec.capture2e(env, exe, stdin_data:"
    assert_includes source, "rescue Master::Io::Exec::TimeoutError"
    refute_match(/Timeout\.timeout\(PIPE_TIMEOUT_SECONDS\).*Open3\.capture2e/m, source)
  end

  # bin/dev-bootstrap is the constrained-environment answer bin/ruby cannot
  # give: bin/ruby probes the Rubies a macOS workstation already has, while an
  # agent container has nothing to probe and no root to install with. The
  # contract is pinned here as a process: a pin wins, a host Ruby in the
  # Gemfile's range wins, a previously built .tools Ruby wins, and a host with
  # none names the refusal instead of reaching for the network.
  def test_dev_bootstrap_execs_the_operators_pin_verbatim
    Dir.mktmpdir do |dir|
      fake = File.join(dir, "fake_ruby")
      File.write(fake, "#!/bin/sh\necho \"FAKE $*\"\n")
      File.chmod(0o755, fake)

      out, status = Open3.capture2e({ "PUB5_RUBY" => fake }, File.join(ROOT, "bin", "dev-bootstrap"), "-Itest", "test/x.rb")

      assert status.success?, out
      assert_includes out, "FAKE -Itest test/x.rb"
    end
  end

  def test_dev_bootstrap_selects_the_best_host_ruby_in_range
    Dir.mktmpdir do |dir|
      old = File.join(dir, "ruby329")
      new = File.join(dir, "ruby336")
      File.write(old, <<~SH)
        #!/bin/sh
        case " $* " in *" print RUBY_VERSION "*) printf "3.2.9" ;; *) echo OLD-PINNED ;; esac
      SH
      File.write(new, <<~SH)
        #!/bin/sh
        case " $* " in *" print RUBY_VERSION "*) printf "3.3.6" ;; *) echo NEW-PINNED ;; esac
      SH
      [old, new].each { |path| File.chmod(0o755, path) }

      # The operator's explicit pin must not decide this race; these tests
      # stage their own candidates and an inherited PUB5_RUBY would win first.
      out, = Open3.capture2e({ "PATH" => "#{dir}:/usr/bin:/bin", "PUB5_RUBY" => nil,
                               "MASTER_RUBY_CANDIDATES" => "#{new}:#{old}" },
                             File.join(ROOT, "bin", "dev-bootstrap"), "hello")

      assert_includes out, "NEW-PINNED", "the newest in-range Ruby must win, got: #{out}"
      refute_includes out, "OLD-PINNED"
    end
  end

  def test_dev_bootstrap_rejects_a_ruby_outside_the_gemfile_range
    Dir.mktmpdir do |dir|
      stale = File.join(dir, "ruby278")
      File.write(stale, <<~SH)
        #!/bin/sh
        case " $* " in *" print RUBY_VERSION "*) printf "2.7.8" ;; *) echo STALE-PINNED ;; esac
      SH
      File.chmod(0o755, stale)

      # Run the copy so a previous build under MASTER/.tools cannot answer in
      # place of the refusal this test proves.
      script = copied_bootstrap(dir)

      out, status = Open3.capture2e({ "PATH" => "/usr/bin:/bin", "PUB5_RUBY" => nil,
                                      "MASTER_RUBY_CANDIDATES" => stale,
                                      "MASTER_DEV_BOOTSTRAP_BUILD" => "0" },
                                    script)

      refute status.success?, "a 2.7 interpreter is outside the Gemfile's range"
      assert_includes out, "no Ruby >= 3.3"
      refute_includes out, "STALE-PINNED", "an out-of-range Ruby was exec'd"
    end
  end

  # A copy of dev-bootstrap under a scratch MASTER, so the script's own ROOT,
  # and with it the step-3 .tools build, points at the scratch and not at this
  # checkout — which may carry a Ruby a refusal test must not see.
  def copied_bootstrap(dir)
    bin_dir = File.join(dir, "MASTER", "bin")
    FileUtils.mkdir_p(bin_dir)
    script = File.join(bin_dir, "dev-bootstrap")
    FileUtils.cp(File.join(ROOT, "bin", "dev-bootstrap"), script)
    script
  end

  def test_dev_bootstrap_prefers_a_ruby_it_already_built
    Dir.mktmpdir do |dir|
      master = File.join(dir, "MASTER")
      bin_dir = File.join(master, "bin")
      tools_bin = File.join(master, ".tools", "ruby", "bin")
      FileUtils.mkdir_p(bin_dir)
      FileUtils.mkdir_p(tools_bin)
      FileUtils.cp(File.join(ROOT, "bin", "dev-bootstrap"), File.join(bin_dir, "dev-bootstrap"))
      File.write(File.join(tools_bin, "ruby"), <<~SH)
        #!/bin/sh
        echo "BUILT-RUBY ld=$LD_LIBRARY_PATH args=$*"
      SH
      File.chmod(0o755, File.join(tools_bin, "ruby"))

      out, status = Open3.capture2e({ "PATH" => "/usr/bin:/bin", "PUB5_RUBY" => nil,
                                      "MASTER_RUBY_CANDIDATES" => "" },
                                    File.join(master, "bin", "dev-bootstrap"), "-v")

      assert status.success?, out
      assert_includes out, "BUILT-RUBY"
      assert_includes out, "ld=#{File.join(master, '.tools', 'ruby', 'lib')}"
    end
  end

  def test_dev_bootstrap_names_the_refusal_when_building_is_disabled
    Dir.mktmpdir do |dir|
      env = {
        "PATH" => "/usr/bin:/bin",
        "PUB5_RUBY" => nil,
        # This host may carry an in-range Ruby at the probed fixed paths; the
        # seam list replaces that probe so the host stays out of the proof.
        "MASTER_RUBY_CANDIDATES" => File.join(dir, "absent-ruby"),
        "MASTER_DEV_BOOTSTRAP_BUILD" => "0",
        "HOME" => Dir.mktmpdir,
      }
      script = copied_bootstrap(dir)
      out, status = Open3.capture2e(env, script)

      refute status.success?, "a host with no Ruby must not report success"
      assert_includes out, "no Ruby >= 3.3"
      assert_includes out, "MASTER_DEV_BOOTSTRAP_BUILD=0"
    end
  ensure
    env && env["HOME"] && Dir.rmdir(env["HOME"]) rescue nil
  end

  def test_dev_bootstrap_is_posix_sh_and_ignores_tools_checkouts
    source = File.read(File.join(ROOT, "bin", "dev-bootstrap"))
    syntax, status = Open3.capture2e("sh", "-n", File.join(ROOT, "bin", "dev-bootstrap"))

    assert status.success?, "bin/dev-bootstrap is not valid POSIX sh: #{syntax}"
    assert_includes source, "https://cache.ruby-lang.org/pub/ruby/3.3/"
    assert_includes source, "--with-yaml-dir"
    code = source.lines.reject { |line| line.strip.start_with?("#") }.join
    refute_includes code, "sudo", "the bootstrap must never need root"
  end

  def test_crawl_browser_probe_uses_the_bounded_executor
    source = File.read(File.join(ROOT, "tools", "rails", "crawl_probe.rb"))

    assert_includes source, "Master::Io::Exec.capture2e(env, \"bundle\", *args"
    assert_includes source, "rescue Master::Io::Exec::TimeoutError"
    refute_includes source, 'require "timeout"'
  end

  def test_smoke_web_passes_against_a_ready_face
    with_fake_face(ready: true) do |url|
      out, status = run_smoke_web(url)

      assert status.success?, out
      assert_includes out, "wait for bootstrap"
      assert_match(/state=clean checks=\d+/, out)
    end
  end

  def test_smoke_web_fails_on_a_warming_face
    with_fake_face(ready: false) do |url|
      out, status = run_smoke_web(url)

      refute status.success?, out
      assert_includes out, "warming page"
    end
  end

  def test_smoke_web_skips_when_nothing_listens
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }

    out, status = run_smoke_web("http://127.0.0.1:#{port}")

    assert status.success?, out
    assert_includes out, "reason=not_listening"
  end

  private

  def copy_script(repo, name)
    bin = File.join(repo, "MASTER", "bin")
    FileUtils.mkdir_p(bin)
    FileUtils.cp(File.join(ROOT, "bin", name), bin)
    File.join(bin, name)
  end

  def cleanup_fixture(repo)
    script = copy_script(repo, "cleanup")
    # bin/cleanup boots through lib/boot/entrypoint, which writes MASTER/.master/;
    # both are ignored as the checkout ignores them, so the fixture stays clean.
    File.symlink(File.join(ROOT, "lib"), File.join(repo, "MASTER", "lib"))
    File.write(File.join(repo, ".gitignore"), "MASTER/reports/\nMASTER/lib\nMASTER/.master/\n")
    File.write(File.join(repo, "test_shot.jpg"), "jpg")
    git(repo, "init", "-q")
    git(repo, "add", ".")
    git(repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "fixture")
    script
  end

  def git(repo, *argv)
    _, status = Open3.capture2e("git", "-C", repo, *argv)
    assert status.success?, "git #{argv.join(' ')} failed in the fixture"
  end

  def run_smoke_web(url)
    env = {
      "MASTER_WEB_URL" => url, "PROBE_TOKEN" => "t" * 43,
      "MASTER_SMOKE_WEB_WARM_S" => "1", "MASTER_SMOKE_WEB_POLL_S" => "1", "MASTER_SMOKE_WEB_READ_S" => "5"
    }
    Open3.capture2e(env, RbConfig.ruby, File.join(ROOT, "bin", "smoke-web"))
  end

  # A face that answers every path smoke-web asks for, either booted or still
  # showing the warming page.
  def with_fake_face(ready:)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        client = server.accept
        request = client.gets.to_s
        headers = {}
        while (line = client.gets) && line != "\r\n"
          key, value = line.split(":", 2)
          headers[key.downcase] = value.to_s.strip
        end
        client.write(response_for(request.split[1].to_s, headers, ready:))
        client.close
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        next
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}"
  ensure
    thread&.kill
    server&.close
  end

  def response_for(path, headers, ready:)
    case path
    when "/up" then http(200, "ok")
    when "/" then http(200, ready ? '<canvas id="face"></canvas><script>ensurePrimer()</script>' : "Starting up")
    when "/master_events.js", "/shortcut_sheet.js" then http(200, "//")
    when "/chat/metrics" then metrics(headers)
    when "/events/stream" then http(200, "data: {}\n\n", type: "text/event-stream")
    else http(404, "")
    end
  end

  def metrics(headers)
    return http(401, "{}") unless headers["x-token"]

    keys = %w[model tokens uptime open_breakers cache_efficiency model_quota]
    http(200, JSON.generate(keys.to_h { |key| [key, 0] }), type: "application/json")
  end

  def http(code, body, type: "text/html")
    "HTTP/1.1 #{code} X\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  end
end
