# frozen_string_literal: true

require_relative "minitest_helper"
require_relative "../../lora/quality"

# A sitting is a deliberate photograph: it must declare its framing, lens or
# distance, light, moment and eye-line, because an axis left unnamed is an
# axis the model fills with the average of its training data. This gate keeps
# every current and future sitting honest.
class TestStudioLoraSceneDesign < Minitest::Test
  Quality = Studio::Lora::Quality

  def test_every_shipped_sitting_declares_all_five_axes
    report = Quality.audit_scene_design
    assert_equal "PASS", report.fetch("state")
    assert_equal 28, report.fetch("scene_count")
    failures = report.fetch("scenes").select { |row| row["state"] == "FAIL" }
    assert_empty failures, failures.map { |row| "#{row["id"]}: #{row["missing"].join(", ")}" }.join("; ")
  end

  def test_a_sitting_missing_axes_fails_with_the_axes_named
    body = "a portrait of the subject in a room, 50mm"
    report = Quality.audit_scene_design(scenes: [body], subject_scenes: {})
    assert_equal "FAIL", report.fetch("state")
    missing = report.fetch("scenes").first.fetch("missing")
    assert_includes missing, "framing"
    assert_includes missing, "light"
    assert_includes missing, "moment"
    assert_includes missing, "eye_line"
    refute_includes missing, "lens_or_distance"
  end

  def test_distance_satisfies_the_projection_axis_without_a_lens_label
    body = "a head-and-shoulders portrait from three metres, soft window light, " \
           "a quiet smile, eyes on the lens"
    report = Quality.audit_scene_design(scenes: [body], subject_scenes: {})
    assert_equal "PASS", report.fetch("state")
  end

  def test_eye_line_accepts_direct_to_lens_phrasing
    body = "a waist-up portrait, 85mm, hard daylight, an amused expression, " \
           "intimate direct-to-lens framing"
    report = Quality.audit_scene_design(scenes: [body], subject_scenes: {})
    assert_equal "PASS", report.fetch("state")
  end
end
