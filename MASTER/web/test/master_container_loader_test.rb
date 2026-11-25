# frozen_string_literal: true

require "test_helper"

# A Rails task is not a server. vps_deploy_master.sh runs db:prepare under a
# different uid than the service, and the container it built refused the
# service-owned state root on every deploy.
class MasterContainerLoaderTest < ActiveSupport::TestCase
  def with_argv(*argv)
    saved = ARGV.dup
    ARGV.replace(argv)
    yield
  ensure
    ARGV.replace(saved)
  end

  test "rails tasks build no container" do
    with_argv("db:prepare") { assert MasterContainerLoader.task_run? }
    with_argv("assets:precompile") { assert MasterContainerLoader.task_run? }
  end

  test "a server invocation still builds one" do
    with_argv { refute MasterContainerLoader.task_run? }
    with_argv("--bind", "http://127.0.0.1:53187") { refute MasterContainerLoader.task_run? }
  end
end
