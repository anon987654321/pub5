# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require "tmpdir"
require_relative "../tools/rails/triangle"

class TestTriangleOwnership < Minitest::Test
  def test_apps_use_the_shared_installed_ruby_and_bundler
    assert_equal Operator::RubyRunner.ruby_cmd, Deploy::Triangle::RUBY
    assert_equal Operator::RubyRunner.bundle_cmd, Deploy::Triangle::BUNDLE
  end

  # A server left behind by a killed /fix run answers /up like a live one. The
  # triangle has to know whose tree it was started in before trusting it.
  def test_listener_reports_the_directory_the_server_was_started_in
    Dir.mktmpdir do |dir|
      port = TCPServer.open("127.0.0.1", 0) { |probe| probe.addr[1] }
      pid = Process.spawn(RbConfig.ruby, "-rsocket", "-e", "TCPServer.new('127.0.0.1', #{port}); sleep", chdir: dir, out: File::NULL, err: File::NULL)
      begin
        found = nil
        50.times do
          found = Deploy::Triangle.listener(port)
          break if found

          sleep 0.1
        end

        refute_nil found, "nothing was found listening on #{port}"
        assert_equal pid, found[:pid]
        assert_equal File.realpath(dir), File.realpath(found[:cwd])
      ensure
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
  end

  def test_down_escalates_the_owned_group_and_removes_files_only_after_exit
    Dir.mktmpdir("triangle-down") do |dir|
      app = { name: "brgen", port: 38_182, dir: }
      pid_path = File.join(dir, "brgen.pid")
      owner_path = "#{pid_path}.owner"
      code = "Signal.trap('TERM', 'IGNORE'); sleep 30"
      pid = Process.spawn(RbConfig.ruby, "-e", code, pgroup: true, out: File::NULL, err: File::NULL)
      waiter = Process.detach(pid)
      File.write(pid_path, "#{pid}\\n")
      File.write(owner_path, "#{Process.pid} #{pid}\\n")

      failed = with_app(app, pid_path) { Deploy::Triangle.down(["brgen"]) }

      assert_empty failed
      refute File.exist?(pid_path)
      refute File.exist?(owner_path)
      refute waiter.alive?
      refute process_group_alive?(pid)
    ensure
      Process.kill("KILL", -pid) rescue nil if defined?(pid) && pid
      waiter&.join(1) if defined?(waiter)
    end
  end

  def test_down_keeps_pid_and_owner_lease_when_group_exit_is_unconfirmed
    Dir.mktmpdir("triangle-down") do |dir|
      app = { name: "brgen", port: 38_182, dir: }
      pid_path = File.join(dir, "brgen.pid")
      owner_path = "#{pid_path}.owner"
      File.write(pid_path, "41352\\n")
      File.write(owner_path, "#{Process.pid} 41352\\n")

      failed = with_app(app, pid_path) do
        Master::Fix::ServerLeases.stub(:stop_process_group, false) do
          Deploy::Triangle.down(["brgen"])
        end
      end

      assert_equal ["brgen"], failed
      assert_equal "41352\\n", File.read(pid_path)
      assert File.exist?(owner_path)
    end
  end

  def test_down_without_pid_file_only_stops_a_verified_isolated_listener_group
    Dir.mktmpdir("triangle-down") do |dir|
      app = { name: "brgen", port: 38_182, dir: }
      pid_path = File.join(dir, "missing.pid")
      pid = Process.spawn(RbConfig.ruby, "-e", "Signal.trap('TERM', 'IGNORE'); sleep 30",
                          pgroup: true, out: File::NULL, err: File::NULL)
      waiter = Process.detach(pid)
      listener = { pid:, cwd: dir }

      failed = with_app(app, pid_path) do
        Deploy::Triangle.stub(:listener, listener) { Deploy::Triangle.down(["brgen"]) }
      end

      assert_empty failed
      refute waiter.alive?
      refute process_group_alive?(pid)
    ensure
      Process.kill("KILL", -pid) rescue nil if defined?(pid) && pid
      waiter&.join(1) if defined?(waiter)
    end
  end

  def test_down_refuses_a_listener_that_is_not_its_own_process_group_leader
    Dir.mktmpdir("triangle-down") do |dir|
      app = { name: "brgen", port: 38_182, dir: }
      pid_path = File.join(dir, "missing.pid")
      pid = Process.spawn(RbConfig.ruby, "-e", "sleep 30", out: File::NULL, err: File::NULL)
      waiter = Process.detach(pid)
      listener = { pid:, cwd: dir }

      failed = with_app(app, pid_path) do
        Deploy::Triangle.stub(:listener, listener) { Deploy::Triangle.down(["brgen"]) }
      end

      assert_equal ["brgen"], failed
      assert waiter.alive?, "a process outside its own PGID must not be signalled"
    ensure
      Process.kill("TERM", pid) rescue nil if defined?(pid) && pid
      waiter&.join(1) if defined?(waiter)
    end
  end

  def with_app(app, pid_path)
    Deploy::Triangle.stub(:selected, [app]) do
      Deploy::Triangle.stub(:pid_file, pid_path) { yield }
    end
  end

  def process_group_alive?(pid)
    Process.kill(0, -pid)
    true
  rescue Errno::ESRCH
    false
  end

  def test_only_sibling_agent_worktrees_are_reaped
    sibling = Deploy::Triangle::SIBLING_WORKTREE

    assert_match sibling, "/Users/mac/Documents/GitHub/pub5-fix-rails3/RAILS/brgen"
    refute_match sibling, "/Users/mac/Documents/GitHub/pub5/RAILS/brgen"
    refute_match sibling, "/srv/other/RAILS/brgen"
  end

  def test_a_port_nobody_holds_has_no_listener
    port = TCPServer.open("127.0.0.1", 0) { |probe| probe.addr[1] }

    assert_nil Deploy::Triangle.listener(port)
  end
  # Built CSS is git-ignored; an app that has it must not be rebuilt on every boot.
  def test_css_is_not_rebuilt_when_it_is_already_built
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app", "assets", "stylesheets"))
      FileUtils.mkdir_p(File.join(dir, "app", "assets", "builds"))
      File.write(File.join(dir, "app", "assets", "stylesheets", "application.scss"), "")
      File.write(File.join(dir, "app", "assets", "builds", "application.css"), "")

      assert Deploy::Triangle.build_css({ name: "x", dir: })
    end
  end

  def test_an_app_without_application_scss_needs_no_build
    Dir.mktmpdir { |dir| assert Deploy::Triangle.build_css({ name: "master", dir: }) }
  end
end
