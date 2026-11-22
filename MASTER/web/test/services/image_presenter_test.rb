# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require "tmpdir"

class ImagePresenterTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\0".b * 64)

  def upload
    Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", true, original_filename: "face.png")
  end

  # /chat/photo is open to visitors; only an operator's upload runs postpro.
  test "a visitor's photo is stored as uploaded and postpro never starts" do
    presenter = ImagePresenter.new(process: false)
    ran = false
    presenter.define_singleton_method(:postpro_photo) { |*| ran = true }

    status, payload = presenter.store(upload)

    assert_equal :ok, status
    assert_equal false, payload[:processed]
    refute ran
  end

  test "a descendant holding the output pipe is stopped under the same deadline" do
    Dir.mktmpdir("postpro-pipe") do |dir|
      child_pid_file = File.join(dir, "descendant.pid")
      child_code = "Signal.trap('TERM', 'IGNORE'); File.write(#{child_pid_file.dump}, [Process.pid, Process.getpgrp].join(' ')); sleep 30"
      parent_code = "Process.spawn(RbConfig.ruby, '-e', #{child_code.dump}); until File.file?(#{child_pid_file.dump}); sleep 0.005; end; puts 'parent exited'; STDOUT.flush; exit 0"
      presenter = ImagePresenter.new
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      output, status = presenter.send(
        :run_bounded, [RbConfig.ruby, "-e", parent_code], chdir: dir, timeout_s: 0.2
      )

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      _child, group = File.read(child_pid_file).split.map { |value| Integer(value, 10) }
      assert_nil status, "an inherited pipe held open past the deadline must be reported as timeout"
      assert_includes output, "parent exited"
      assert_operator elapsed, :<, 4.0, "a descendant holding stdout must not turn the timeout into an unbounded wait"
      assert_process_group_gone(group)
    end
  end

  test "a grade that outlives its limit is killed, not waited for" do
    presenter = ImagePresenter.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    _out, status = presenter.send(:run_bounded, [ RbConfig.ruby, "-e", "sleep 30" ], chdir: Dir.tmpdir, timeout_s: 1)

    assert_nil status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
  end

  private

  def assert_process_group_gone(group)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    loop do
      begin
        Process.kill(0, -group)
      rescue Errno::ESRCH
        return
      end
      flunk "postpro descendant process group #{group} survived timeout cleanup" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
  end
end
