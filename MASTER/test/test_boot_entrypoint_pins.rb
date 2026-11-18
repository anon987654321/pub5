# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# boot/entrypoint.rb activates the lockfile's pinned default gems (json, date)
# before `require "time"` loads date. On vm23 (Ruby 3.4) the default date is
# older than the lock's, and Bundler.setup died on "already activated date
# 3.4.1" until the pin ran first (2026-10-12, tts-worker --selftest).
#
# Complementarily, `require "time"` itself must run only after bundler/setup:
# on a fresh checkout the retry pin cannot see the just-installed store, so
# loading time before setup activated the interpreter's default date and
# Bundler.setup crashed with the same "already activated date" error
# (2026-11-18, self-test boot on a Ruby 3.4.6 sandbox).
class TestBootEntrypointPins < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENTRYPOINT = File.join(ROOT, "lib", "boot", "entrypoint.rb")

  def locked(name)
    File.read(File.join(ROOT, "Gemfile.lock"), encoding: "UTF-8")[/^    #{name} \(([\d.]+)\)$/, 1]
  end

  def test_the_locked_default_gems_are_the_ones_active_after_the_entrypoint_loads
    %w[json date].each do |name|
      pin = locked(name)
      next unless pin && Gem::Specification.find_all_by_name(name, pin).any?

      out, status = Open3.capture2e(RbConfig.ruby, "-e", "require #{ENTRYPOINT.inspect}; print Gem.loaded_specs[#{name.inspect}]&.version")
      assert_predicate status, :success?, out
      assert_equal pin, out.strip, "#{name} must be on the locked version before Bundler.setup"
    end
  end

  def test_time_is_required_only_after_bundler_setup
    source = File.read(ENTRYPOINT, encoding: "UTF-8")
    setup_at = source.index('require "bundler/setup"')
    time_at = source.index('require "time"')

    refute_nil setup_at, "activate_bundle! must require bundler/setup"
    refute_nil time_at, "time/date must still be loaded by the entrypoint"
    assert_operator setup_at, :<, time_at,
      'require "time" must come after require "bundler/setup" so the locked ' \
      "date is active before time.rb loads it; loading time first activates " \
      "the interpreter's default date and crashes Bundler.setup on a fresh checkout"
  end
end
