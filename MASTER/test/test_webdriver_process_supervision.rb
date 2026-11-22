# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "shellwords"
require "tmpdir"
require_relative "../checks/support/capture_engine"
require_relative "../checks/support/webdriver_engine"

class TestWebDriverProcessSupervision < Minitest::Test
  Engine = Deploy::CaptureEngine::WebDriverEngine

  def test_open_creates_an_isolated_driver_group_and_close_reaps_it
    Dir.mktmpdir("webdriver-driver") do |dir|
      driver = File.join(dir, "fake-geckodriver")
      File.write(
        driver,
        "#!/bin/sh\nexec #{Shellwords.escape(RbConfig.ruby)} -e " \
          "#{Shellwords.escape('Signal.trap("TERM", "IGNORE"); sleep 30')}\n"
      )
      File.chmod(0o700, driver)

      engine = Engine.new(name: "firefox", driver:, caps: { browserName: "firefox" })
      engine.define_singleton_method(:wait_for_driver) { true }
      engine.define_singleton_method(:post) { |_path, **_body| { "value" => { "sessionId" => "session-1" } } }
      engine.define_singleton_method(:post_quietly) { |_path, **_options| nil }
      engine.define_singleton_method(:webdriver_term_grace) { 0.1 }
      engine.define_singleton_method(:webdriver_kill_grace) { 1.0 }
      engine.define_singleton_method(:webdriver_stop_poll) { 0.01 }

      assert_same engine, engine.open
      pid = engine.instance_variable_get(:@pid)
      assert_equal pid, Process.getpgid(pid), "driver must start its own process group"

      assert engine.close
      assert_nil engine.instance_variable_get(:@pid)
      assert_nil engine.instance_variable_get(:@session)
      refute process_group_alive?(pid)
    end
  end

  def test_driver_reaper_stops_renderer_descendants_with_the_leader
    Dir.mktmpdir("webdriver-renderer") do |dir|
      child_file = File.join(dir, "renderer.pid")
      child_code = "Signal.trap('TERM', 'IGNORE'); File.write(#{child_file.dump}, Process.pid.to_s); sleep 30"
      leader_code = <<~RUBY
        Signal.trap("TERM", "IGNORE")
        Process.spawn(RbConfig.ruby, "-e", #{child_code.dump}, out: File::NULL, err: File::NULL)
        sleep 30
      RUBY
      pid = Process.spawn(RbConfig.ruby, "-e", leader_code, pgroup: true, out: File::NULL, err: File::NULL)
      engine = allocated_engine(pid)
      child = wait_for_file(child_file).to_i

      assert_equal pid, Process.getpgid(child)
      assert engine.close
      refute engine.instance_variable_get(:@pid)
      refute process_group_alive?(pid)
    ensure
      Process.kill("KILL", -pid) rescue nil if defined?(pid) && pid
      Process.waitpid(pid) rescue nil if defined?(pid) && pid
    end
  end

  def test_unconfirmed_driver_shutdown_retains_session_and_pid
    engine = allocated_engine(987_654_321)
    engine.define_singleton_method(:stop_driver_group) { |_pid| false }
    engine.define_singleton_method(:post_quietly) { |_path, **_options| nil }

    refute engine.close
    assert_equal 987_654_321, engine.instance_variable_get(:@pid)
    assert_equal "session-1", engine.instance_variable_get(:@session)
  end

  private

  def allocated_engine(pid)
    engine = Engine.allocate
    engine.instance_variable_set(:@name, "firefox")
    engine.instance_variable_set(:@pid, pid)
    engine.instance_variable_set(:@session, "session-1")
    engine.define_singleton_method(:post_quietly) { |_path, **_options| nil }
    engine.define_singleton_method(:webdriver_term_grace) { 0.1 }
    engine.define_singleton_method(:webdriver_kill_grace) { 1.0 }
    engine.define_singleton_method(:webdriver_stop_poll) { 0.01 }
    engine
  end

  def wait_for_file(path, timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until File.file?(path)
      raise "subprocess did not publish #{File.basename(path)}" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
    File.read(path)
  end

  def process_group_alive?(pid)
    Process.kill(0, -pid)
    true
  rescue Errno::ESRCH
    false
  end
end
