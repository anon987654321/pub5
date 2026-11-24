# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../tools/attestation_audit"

class TestAttestationAudit < Minitest::Test
  # A fixture tree standing in for the deploy chain: one stamp that is guarded
  # but never produced (the G1 shape), one that is produced then guarded, one
  # literal that is not attestation-shaped and must be ignored.
  def with_fixture_tree
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "deploy.sh"), <<~SH)
        stamp="$out/.app-build-sha"
        [[ -f $stamp && ! -L $stamp ]] || refuse "no attestation"
        guard="/etc/app/.config-manifest"
        [[ -s $guard ]] || refuse "missing manifest"
      SH
      File.write(File.join(dir, "builder.sh"), <<~SH)
        manifest="/etc/app/.config-manifest"
        cp "$src" "$manifest"
      SH
      File.write(File.join(dir, "notes.rb"), <<~RUBY)
        WELCOME = "hello friend"
      RUBY
      yield dir
    end
  end

  def test_writerless_stamp_is_flagged
    with_fixture_tree do |dir|
      rows = AttestationAudit.audit(dir)
      row = rows.find { |r| r[:literal].end_with?(".app-build-sha") }
      refute_nil row
      assert row[:writerless]
      assert_empty row[:writers]
      assert_includes row[:readers], "deploy.sh:2"
      assert_includes row[:vars], "stamp"
    end
  end

  def test_produced_stamp_is_clean
    with_fixture_tree do |dir|
      row = AttestationAudit.audit(dir).find { |r| r[:literal] == "/etc/app/.config-manifest" }
      refute_nil row
      refute row[:writerless]
      assert_equal ["builder.sh:2"], row[:writers]
    end
  end

  def test_non_attestation_literals_are_ignored
    with_fixture_tree do |dir|
      refs = AttestationAudit.audit(dir).map { |r| r[:literal] }
      refute_includes refs, "hello friend"
    end
  end
end
