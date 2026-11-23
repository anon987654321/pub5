# frozen_string_literal: true

require "minitest/autorun"
load File.expand_path("../bin/vps-admin", __dir__)

class VpsAdminTest < Minitest::Test
  def test_read_only_commands_are_named
    assert_equal [["doas", "df", "-h"]], OpenBSDAdmin.commands_for(["disk"])
    assert_equal [["doas", "pfctl", "-si"]], OpenBSDAdmin.commands_for(["pf", "status"])
    assert_equal [["doas", "syspatch", "-c"]], OpenBSDAdmin.commands_for(["updates"])
    assert_equal [["doas", "pkg_info"]], OpenBSDAdmin.commands_for(["packages"])
    assert_equal [["doas", "sysupgrade", "-n"]], OpenBSDAdmin.commands_for(["upgrade", "stage"])
  end

  def test_upgrade_check_cannot_arm_an_upgrade
    [["upgrade"], ["upgrade", "check"]].each do |argv|
      commands = OpenBSDAdmin.commands_for(argv)

      refute commands.any? { |c| c.include?("sysupgrade") }, "#{argv.join(' ')} must not run sysupgrade, which -n arms for the next boot"
      refute commands.any? { |c| c.first == "doas" }, "a check needs no root"
    end
  end

  def test_service_actions_are_allowlisted
    assert_equal [["doas", "rcctl", "restart", "master"]],
                 OpenBSDAdmin.commands_for(["service", "master", "restart"])
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master", "shell"]) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master;touch /tmp/x", "restart"]) }
  end

  def test_firewall_reload_validates_before_loading
    assert_equal(
      [["doas", "pfctl", "-nf", "/etc/pf.conf"], ["doas", "pfctl", "-f", "/etc/pf.conf"]],
      OpenBSDAdmin.commands_for(["pf", "reload"]),
    )
  end

  def test_arbitrary_commands_are_refused
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["sh", "-c", "id"]) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["service", "master", "exec", "id"]) }
  end

  def test_diagnose_redacts_sensitive_command_line_arguments
    source = "worker --api-key abc123 --password 'secret value' Authorization: Bearer token123 AWS_SECRET_ACCESS_KEY=awssecret"
    redacted = OpenBSDAdmin.redact_diagnostic_output(source)

    refute_includes redacted, "abc123"
    refute_includes redacted, "secret value"
    refute_includes redacted, "token123"
    refute_includes redacted, "awssecret"
    assert_equal 4, redacted.scan("[REDACTED]").length
  end

  def test_reboot_is_one_explicit_action
    assert_equal [["doas", "/sbin/reboot"]], OpenBSDAdmin.commands_for(["reboot"])
  end

  def test_status_is_composed_of_named_commands
    commands = OpenBSDAdmin.commands_for(["status"])
    assert_includes commands, ["hostname"]
    assert_includes commands, ["uptime"]
    assert_includes commands, ["uname", "-a"]
    assert_includes commands, ["doas", "df", "-h"]
  end

  def test_diagnose_is_a_bounded_read_only_incident_snapshot
    commands = OpenBSDAdmin.commands_for(["diagnose"])

    assert_includes commands, ["uptime"]
    assert_includes commands, ["vmstat", "1", "5"]
    assert_includes commands, ["top", "-b", "-n", "1"]
    assert_includes commands, ["ps", "-axww"]
    assert_includes commands, ["doas", "rcctl", "ls", "started"]
    assert_includes commands, ["doas", "rcctl", "ls", "failed"]
    assert_includes commands, ["netstat", "-an", "-f", "inet"]
    assert_includes commands, ["doas", "df", "-h"]
    assert_includes commands, ["doas", "swapctl", "-s"]
    refute commands.flatten.any? { |arg| %w[start stop restart kill pkill reboot].include?(arg) }
    assert_raises(ArgumentError) { OpenBSDAdmin.commands_for(["diagnose", "--apply"]) }
  end
end
