# frozen_string_literal: true

require_relative "test_helper"

# The face attends through one contract (voice.yml face:). The browser
# reads it as MASTER_VOICE_POLICY; the terminal through Voice::Policy.
class TestFaceAwareness < Minitest::Test
  C = Master::Voice::Policy

  def test_the_contract_declares_listening_speaking_and_the_echo_check
    spec = C.awareness
    assert_operator spec.dig("listening", "glance_scale"), :<, 1.0
    assert_operator spec.fetch("heard_hold_ms"), :>, 0
    assert_operator spec.dig("echo_safe", "tts_tail_ms"), :>, 0
  end

  def test_the_mic_is_not_trusted_while_master_is_audible_or_just_finished
    refute C.echo_safe?(playing: true)
    refute C.echo_safe?(playing: false, loading: true)
    refute C.echo_safe?(playing: false, ms_since_tts_end: 100)
    assert C.echo_safe?(playing: false, ms_since_tts_end: 5_000)
    assert C.echo_safe?(playing: false)
  end

  def test_the_browser_feeds_awareness_only_through_the_echo_check
    part3 = File.read(File.join(Master::ROOT, "..", "MASTER", "web", "public", "face.part3.txt"))
    part5 = File.read(File.join(Master::ROOT, "..", "MASTER", "web", "public", "face.part5.txt"))
    assert_includes part3, "function faceEchoSafe"
    assert_includes part5, "if (faceEchoSafe()) State.heardAt"
    refute_match(/State\.heardAt\s*=(?!.*faceEchoSafe)/, part5.lines.reject { |l| l.include?("faceEchoSafe") }.join)
  end

  def test_the_mouth_shapes_come_from_the_contract_for_both_faces
    assert_equal "A", C.viseme_for("a")
    assert_equal "M", C.viseme_for("b")
    assert_equal "E", C.viseme_for("t")
    assert_equal 0.0, C.mouth_shape("M").fetch("open")
    assert_operator C.mouth_shape("I").fetch("wide"), :>, 0
    assert_operator C.mouth_shape("U").fetch("wide"), :<, 0
    assert_equal 0.0, C.mouth_shape("nonsense").fetch("wide")
  end

  def test_laws_yml_no_longer_carries_the_face_settings
    laws = File.read(File.join(Master::ROOT, "data", "laws.yml"))
    refute_includes laws, "closed_letters"
    refute_includes laws, "heard_hold_ms"
  end

  def test_the_browser_receives_both_blocks_in_the_voice_payload
    payload = C.browser_payload
    assert_equal C.awareness, payload.fetch(:awareness)
    assert_equal C.mouth, payload.fetch(:mouth)
  end

  def test_the_browser_mouth_uses_the_contract_wide_gain
    shader = File.read(File.join(Master::ROOT, "..", "MASTER", "web", "public", "face.part2.txt"))
    loop = File.read(File.join(Master::ROOT, "..", "MASTER", "web", "public", "face.part3.txt"))
    assert_includes shader, "uMouthWide"
    assert_includes loop, "mouthSpec?.wide_gain"
  end
end
