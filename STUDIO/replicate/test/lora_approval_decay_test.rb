# frozen_string_literal: true

require_relative "minitest_helper"

begin
  require "date"
  require_relative "../../lora/quality"
rescue LoadError => error
  warn "skipping approval decay tests: #{error.message}"
  return
end

# A likeness approval is a decision about a face at a point in time. The pure
# state machine is pinned here: no evidence, fresh evidence, old evidence,
# evidence for the wrong profile and an approved version no receipt covers.
class TestStudioLoraApprovalDecay < Minitest::Test
  Quality = Studio::Lora::Quality
  Today = Date.new(2026, 11, 24)

  def decide(approved:, receipt:, profile: "balanced", max_age: 90)
    Quality.approval_state(
      approved_version: approved, receipt: receipt,
      current_profile: profile, max_age_days: max_age, today: Today
    )
  end

  def receipt(version: "owner/model:abc", profile: "balanced", date: Date.new(2026, 11, 20))
    { "model_version" => version, "inference_profile" => profile, "reviewed_at" => date }
  end

  def test_no_approval_and_no_receipt_is_never_reviewed
    assert_equal "NEVER_REVIEWED", decide(approved: nil, receipt: nil)
  end

  def test_fresh_receipt_on_the_active_profile_is_current
    assert_equal "CURRENT", decide(approved: "owner/model:abc", receipt: receipt)
  end

  def test_old_receipt_is_stale_by_age
    old = receipt(date: Date.new(2026, 8, 1))
    assert_equal "STALE_AGE", decide(approved: "owner/model:abc", receipt: old)
  end

  def test_receipt_on_a_retired_profile_is_stale_by_profile
    drifted = receipt(profile: "identity")
    assert_equal "STALE_PROFILE", decide(approved: "owner/model:abc", receipt: drifted)
  end

  def test_approved_version_without_a_matching_receipt_is_unreviewed
    other = receipt(version: "owner/model:zzz")
    assert_equal "UNREVIEWED_VERSION", decide(approved: "owner/model:abc", receipt: other)
    assert_equal "UNREVIEWED_VERSION", decide(approved: "owner/model:abc", receipt: nil)
  end

  def test_age_boundary_is_inclusive_of_the_max_age
    boundary = receipt(date: Today - 90)
    assert_equal "CURRENT", decide(approved: "owner/model:abc", receipt: boundary)
    assert_equal "STALE_AGE", decide(approved: "owner/model:abc", receipt: receipt(date: Today - 91))
  end
end
