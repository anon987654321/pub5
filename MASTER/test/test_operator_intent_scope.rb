# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/operator_intent"

# F7 and F8 from the 2026-11-23 dry-run: a full-stack request that names STUDIO
# must say STUDIO was left out, and the polite-question consent shortcut can be
# switched off so only a literal --confirm authorizes production.
class TestOperatorIntentScope < Minitest::Test
  Intent = Master::CLI::OperatorIntent
  FULL = "hi, can you please redeploy OPENBSD, RAILS, STUDIO, and MASTER/web on vm23?"

  def test_studio_note_is_prepended_once_to_a_full_stack_reply
    result = Master::Result.ok({ rendered: "ok", output: "ok" })
    noted = Intent.with_studio_note(Intent.with_studio_note(result, FULL), FULL).value!
    assert_equal 1, noted[:output].scan(Intent::STUDIO_SCOPE_NOTE).size
    assert noted[:rendered].end_with?("ok")
  end

  def test_other_requests_and_errors_pass_through_untouched
    result = Master::Result.ok({ rendered: "ok", output: "ok" })
    assert_same result, Intent.with_studio_note(result, "redeploy RAILS on vm23")
    err = Master::Result.err("boom")
    assert_same err, Intent.with_studio_note(err, FULL)
  end

  def test_strict_confirm_turns_off_the_polite_question_shortcut
    assert Intent.direct_full_stack_confirmation?(FULL)
    ENV["MASTER_DEPLOY_STRICT_CONFIRM"] = "1"
    refute Intent.direct_full_stack_confirmation?(FULL)
  ensure
    ENV.delete("MASTER_DEPLOY_STRICT_CONFIRM")
  end
end
