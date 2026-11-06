# frozen_string_literal: true

require_relative "../test_helper"

# World#exec checks argv[0]'s basename, and a command that runs
# RbConfig.ruby passes the interpreter's own path. On the OpenBSD box that
# is /usr/local/bin/ruby34 (ruby is a symlink to it), so a manifest that
# declares only ruby refuses bin/check's test stage there.
class BoxRubyTest < Minitest::Test
  RUBY_RUNNERS = %w[check test port-laws gate].freeze

  def test_every_command_that_runs_rbconfig_ruby_may_run_the_boxes_ruby34
    commands = Core::Registry.load(:commands).fetch("commands")
    RUBY_RUNNERS.select { |name| commands.key?(name) }.each do |name|
      manifest = Core::Manifest.new(name:, verbs: commands.dig(name, "verbs"), protected_paths: [])
      %w[ruby ruby34].each { |ruby| assert_equal ruby, manifest.check!(:exec, ruby), "#{name} must declare #{ruby}" }
    end
  end
end
