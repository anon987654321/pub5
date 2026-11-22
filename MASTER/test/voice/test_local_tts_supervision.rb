# frozen_string_literal: true

require "tmpdir"
require_relative "../test_helper"

# The warm local TTS server is intentionally long-lived, but its process
# ownership must remain observable so one failed start does not poison a session.
class TestLocalTtsSupervision < Minitest::Test
  Tts = Master::Voice::LocalTts

  def test_a_live_server_is_not_duplicated_and_an_exited_child_can_be_restarted
    previous_waiter = Tts.instance_variable_get(:@server_waiter)
    waiters = []
    Tts.instance_variable_set(:@server_waiter, nil)

    Dir.mktmpdir("local-tts-supervision") do |root|
      executable = File.join(root, "fake-server")
      File.write(executable, "#!/bin/sh\nexec /bin/sleep 60\n")
      File.chmod(0o700, executable)
      entry = { "server" => "http://127.0.0.1:11434" }

      Tts.stub(:server_bin, executable) do
        assert Tts.start_server(entry, root:)
        first = Tts.instance_variable_get(:@server_waiter)
        refute_nil first
        waiters << first

        assert Tts.start_server(entry, root:)
        assert_same first, Tts.instance_variable_get(:@server_waiter),
                    "a live local server must not be spawned twice"

        Process.kill("TERM", first.pid)
        wait_until { !first.alive? }

        assert Tts.start_server(entry, root:),
               "a later request must restart an exited local server"
        second = Tts.instance_variable_get(:@server_waiter)
        refute_nil second
        refute_same first, second
        assert second.alive?
        waiters << second
      end
    end
  ensure
    waiters.each { |waiter| stop_waiter(waiter) }
    Tts.instance_variable_set(:@server_waiter, previous_waiter)
  end

  private

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for the local TTS child" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end

  def stop_waiter(waiter)
    return unless waiter

    if waiter.alive?
      Process.kill("TERM", waiter.pid)
      waiter.join(1)
      if waiter.alive?
        Process.kill("KILL", waiter.pid)
        waiter.join(1)
      end
    end
    waiter.value
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end
end
