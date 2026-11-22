# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/device/wake_signal"

class TestDeviceWakeSignal < Minitest::Test
  def test_publish_uses_the_shared_private_atomic_writer
    Dir.mktmpdir do |root|
      calls = []
      writer = Master::Io::AtomicWrite.method(:write_atomic)
      instrumented = lambda do |path, content, **options|
        calls << [path, content, options]
        writer.call(path, content, **options)
      end
      event = nil
      Master::Io::AtomicWrite.stub(:write_atomic, instrumented) do
        event = Master::Device::WakeSignal.publish(root:, phrase: "hey mochi", at: 123.45)
      end

      assert_equal 1, calls.length
      assert_equal File.join(root, Master::Device::WakeSignal::PATH), calls.first.first
      assert_equal 0o600, calls.first.last.fetch(:mode)
      assert_equal event[:id], Master::Device::WakeSignal.read(root:)[:id]
      assert_equal 0o600, File.stat(calls.first.first).mode & 0o777
      assert_empty Dir.children(File.join(root, ".master")).grep(/master_atomic|wake-event-/)
    end
  end

  def test_missing_signal_is_empty
    Dir.mktmpdir do |root|
      assert_nil Master::Device::WakeSignal.read(root:)
    end
  end
end
