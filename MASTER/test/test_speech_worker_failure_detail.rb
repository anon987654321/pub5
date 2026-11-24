# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/voice/speech_worker"

# The one-shot TTS worker re-execs MASTER, so its stderr opens with deps0:
# boot lines that buried the real cause in the operator's error (2026-11-23).
class TestSpeechWorkerFailureDetail < Minitest::Test
  Host = Class.new { include Master::Voice::SpeechWorker }

  def detail(err) = Host.new.send(:worker_failure_detail, err)

  def test_boot_banner_lines_are_dropped_when_the_cause_follows
    err = "deps0: bundle ok\ndeps0: bundle ok\ntts0: one-shot synthesis produced no audio\n"
    assert_equal "tts0: one-shot synthesis produced no audio", detail(err)
  end

  def test_a_bare_deps0_failure_is_the_cause_and_stays
    assert_equal "deps0: gem missing", detail("deps0: gem missing\n")
  end

  def test_empty_stderr_stays_empty
    assert_equal "", detail(nil)
  end
end
