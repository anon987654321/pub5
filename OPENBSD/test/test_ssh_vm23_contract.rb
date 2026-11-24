# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class SshVm23ContractTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../lib/ssh_vm23.sh", __dir__), encoding: "UTF-8")

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
  def test_repo_root_resolves_above_openbsd_lib
    assert_includes SOURCE, 'SSH_VM23_REPO_ROOT=${SSH_VM23_SOURCE:h:h:h}'
    refute_includes SOURCE, 'SSH_VM23_REPO_ROOT=${SSH_VM23_SOURCE:h:h}'
  end

  def test_shared_ssh_library_and_operator_expose_one_preflight_command
    operator = File.read(File.expand_path("../../MASTER/bin/operator", __dir__))
    assert_includes operator, 'when "rtfm"'
    assert_includes operator, 'preflight.refusal_for_ssh_argv'
    assert_includes operator, 'preflight.refusal_for_command'
  end
  def test_master_reads_the_canonical_vm23_endpoint_and_key_from_operator_authority
    root = File.expand_path("../..", __dir__)
    authority = YAML.safe_load(File.read(File.join(root, "OPENBSD/data/operator.yml")), aliases: false)
    operator = File.read(File.join(root, "MASTER/bin/operator"))

    assert_equal "dev@brgen.no", authority.dig("meta", "vps")
    assert_equal "~/.ssh/id_ed25519_brgen", authority.dig("meta", "ssh_identity_file")
    assert_includes operator, 'operator_runtime_config.fetch("meta").fetch("vps")'
    assert_includes operator, 'operator_runtime_config.fetch("meta").fetch("ssh_identity_file")'
    assert_includes operator, '"IdentitiesOnly=yes"'
    assert_includes operator, '"StrictHostKeyChecking=yes"'
    assert_includes operator, "def ssh_access_refusal"
  end

  def test_master_deploy_probes_vm23_before_local_preflight_and_ci
    operator = File.read(File.expand_path("../../MASTER/bin/operator", __dir__))
    deploy = operator[/when "deploy"\n.*?when "admin"/m]

    assert_includes deploy, "openbsd_target_identity"
    assert_includes deploy, "verify_vm23_identity"
    assert_includes deploy, 'ssh_capture(command, attempts: 1)'
    assert_operator deploy.index("connection_check"), :<, deploy.index("remote_command")
  end

end
