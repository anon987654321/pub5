# frozen_string_literal: true

require_relative "test_helper"

class TestOpenbsdConfig < Minitest::Test
  def setup
    @validator = Master::Ground::OpenbsdConfig.load(root: Master::ROOT)
  end

  def test_loads_validator_table
    assert @validator.known?("pf.conf")
    refute @validator.known?("nginx.conf")
  end

  def test_clean_config_has_no_findings
    findings = @validator.validate("httpd.conf", "server \"x\" {}\n")
    assert_empty findings
  end

  def test_flags_missing_required_pattern
    findings = @validator.validate("pf.conf", "pass all\n")
    missing = findings.select { |f| f.severity == :missing }
    assert(missing.any? { |f| f.message.include?("set skip on lo") })
  end

  def test_warns_on_discouraged_pattern_present
    findings = @validator.validate("sshd_config", "PermitRootLogin yes\n")
    assert(findings.any? { |f| f.severity == :warning && f.message.include?("PermitRootLogin") })
  end

  def test_absent_message_when_recommended_pattern_missing
    findings = @validator.validate("nsd.conf", "server:\nzone:\n")
    assert(findings.any? { |f| f.message.include?("RRL") })
  end

  def test_unknown_config_yields_no_findings
    assert_empty @validator.validate("unknown.conf", "anything")
  end

  def test_full_stack_manual_inventory_covers_tracked_configuration_and_nsd_files
    inventory = Master::Fix::OpenBSDManualPreflight.mirror_configuration_inventory(root: Master::ROOT)
    paths = inventory.map { |entry| entry.fetch("path") }

    assert_includes paths, "OPENBSD/mirror/etc/relayd.conf"
    assert_includes paths, "OPENBSD/mirror/etc/rc.conf.local"
    assert_includes paths, "OPENBSD/mirror/var/nsd/etc/nsd.conf"
    assert(paths.any? { |path| path.end_with?(".zone") })
  end

  def test_inert_litestream_example_is_source_audited_without_fabricated_openbsd_manual
    manuals = Master::Fix::OpenBSDManualPreflight.required_path_manuals(
      "OPENBSD/mirror/etc/litestream.yml"
    )

    assert_equal [], manuals
  end

  def test_full_stack_deploy_detection_is_explicit
    preflight = Master::Fix::OpenBSDManualPreflight
    assert preflight.full_vps_deploy_command?(%w[zsh OPENBSD/bin/vps-deploy all])
    assert preflight.full_vps_deploy_command?(%w[MASTER/bin/operator vps deploy all --remote])
    refute preflight.full_vps_deploy_command?(%w[zsh OPENBSD/bin/vps-deploy brgen])
  end

  def test_full_stack_manual_gate_requires_every_mirror_configuration_source_read
    preflight = { "source_reads" => [], "native_interfaces" => [] }
    refusal = Master::Fix::OpenBSDManualPreflight.mirror_configuration_refusal(
      preflight,
      root: Master::ROOT
    )

    assert_match(/complete source-read receipt for mirror configuration/, refusal)
  end

  def test_validate_file_rejects_unknown_basename
    result = @validator.validate_file("/etc/nginx.conf")
    assert result.err?
  end

  # data/openbsd.yml and OPENBSD/mirror/etc describe the same daemons from two trees.
  # Every config the validator knows must carry its required patterns, so a
  # rule that stops matching the deployed file fails here instead of on the box.
  def test_the_tree_configs_carry_every_required_pattern
    etc = File.expand_path("../../OPENBSD/mirror/etc", __dir__)
    files = Dir.glob(File.join(etc, "**", "*")).select { |f| File.file?(f) && @validator.known?(File.basename(f)) }
    assert_operator files.size, :>=, 5, "expected the OPENBSD/mirror/etc configs the validator knows"

    missing = files.flat_map { |f| @validator.validate_file(f).value!.select { |x| x.severity == :missing } }
    assert_empty missing.map(&:to_s)
  end
end
