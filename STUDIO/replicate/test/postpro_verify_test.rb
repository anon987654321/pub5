# frozen_string_literal: true

require_relative "minitest_helper"

begin
  require_relative "../../postpro/verify"
rescue LoadError => error
  warn "skipping postpro verify tests: #{error.message}"
  return
end

# The reproducibility claim in every grade sidecar needs a check behind it.
# These pin the verdict mapping and the version digest contract; the replay
# itself runs postpro and is exercised on the operator's machine.
class TestPostproVerify < Minitest::Test
  Verify = Postpro::Verify

  def test_grade_version_is_a_twelve_char_hex_digest
    assert_match(/\A[0-9a-f]{12}\z/, Verify.grade_version)
  end

  def test_grade_version_is_stable_within_a_checkout
    assert_equal Verify.grade_version, Verify.grade_version
  end

  def test_verified_only_when_version_matches_and_bytes_match
    assert_equal "VERIFIED", Verify.verdict(receipt_version: "abc123def456", current_version: "abc123def456", byte_match: true)
  end

  def test_mismatch_when_same_code_produces_different_bytes
    assert_equal "MISMATCH", Verify.verdict(receipt_version: "abc123def456", current_version: "abc123def456", byte_match: false)
  end

  def test_version_drift_when_the_code_moved
    assert_equal "VERSION_DRIFT", Verify.verdict(receipt_version: "old000old000", current_version: "abc123def456", byte_match: true)
  end

  def test_not_verifiable_without_a_receipt_version
    assert_equal "NOT_VERIFIABLE", Verify.verdict(receipt_version: nil, current_version: "abc123def456", byte_match: true)
  end
end
