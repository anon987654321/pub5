# frozen_string_literal: true

require "minitest/autorun"

class SshVm23ContractTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../mirror/lib/ssh_vm23.sh", __dir__), encoding: "UTF-8")

  def test_tmux_session_name_is_shell_quoted_before_remote_execution
    assert_includes SOURCE, "typeset quoted_session=${(q)session}"
    refute_match(/tmux has-session -t \$\{session\}/, SOURCE)
    refute_match(/tmux kill-session -t \$\{session\}/, SOURCE)
    refute_match(/tmux new-session -d -s \$\{session\}/, SOURCE)
  end

def test_a_long_session_sends_keepalives
  assert_includes SOURCE, "ServerAliveInterval=15"
  assert_includes SOURCE, "ServerAliveCountMax=8"
  operator = File.read(File.expand_path("../../MASTER/bin/operator", __dir__), encoding: "UTF-8")
  assert_includes operator, "ServerAliveInterval=15"
  assert_includes operator, "ServerAliveCountMax=8"
end

def test_remote_command_payload_remains_quoted
    assert_includes SOURCE, "${(q)cmd}"
  end
  def test_shared_ssh_library_and_operator_expose_one_preflight_command
    operator = File.read(File.expand_path("../../MASTER/bin/operator", __dir__))
    assert_includes operator, 'when "rtfm"'
    assert_includes operator, 'preflight.refusal_for_ssh_argv'
    assert_includes operator, 'preflight.refusal_for_command'
  end

end
