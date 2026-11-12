# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# bin/doctor had no test. It is the tool an operator runs first on a host that
# is behaving oddly, and the thing it reports is a verdict per check — so the
# verdict vocabulary is the part worth pinning.
#
# Driven as a subprocess rather than by loading the file: doctor is a script
# with top-level execution, and requiring it runs every probe against this
# machine. That is also the honest test of an entry point, which the tree has
# already been bitten by twice (test_entrypoint_requires).
class TestDoctor < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOCTOR = File.join(ROOT, "bin", "doctor")

  def run_doctor(env = {})
    Open3.capture2e(env, RbConfig.ruby, DOCTOR, chdir: ROOT)
  end

  def test_doctor_runs_and_reports_every_check
    out, = run_doctor
    assert_match(/^doctor0 at master0: MASTER doctor, \d+ checks$/, out)
    %w[content-dedup api-keys tts-socket voice-utterance web-token key-rotator
       model-quota cache-efficiency provider-catalog].each do |name|
      assert_match(/^doctor\d+ at doctor0: #{Regexp.escape(name)}, (ok|fail|skip)$/, out,
                   "doctor did not report #{name}")
    end
  end

  # A checkout with no audio path must not guess about the ear: the container
  # run says why it measured nothing, in its own word, and the check's own
  # verdict is skip — never the fail that would call a headless host sick.
  def test_voice_utterance_measures_nothing_on_a_headless_checkout
    out, = run_doctor

    assert_match(/^doctor\d+ at doctor0: voice-utterance, skip$/, out)
    assert_match(/voice-utterance, .*(no audio output|cannot be verified from a pipe)/, out)
    refute_match(/^doctor\d+ at doctor0: voice-utterance, fail$/, out,
                 "the ear check failed a host that never had an ear")
  end

  # The verdict is three-valued, and the third one is the reason this test
  # exists. model-quota and cache-efficiency used to answer `ok: true, detail:
  # "module not loaded"` — OK for a check nobody ran — and content-dedup raised
  # into `ok: false`, so a broken instrument read as a real finding.
  def test_a_check_that_measured_nothing_says_so
    source = File.read(DOCTOR)
    assert_match(/state: :unmeasured/, source, "no check can report that it measured nothing")
    refute_match(/state: :pass, detail: "module not loaded"/, source,
                 "a check that did not load is reporting OK")
  end

  def test_unmeasured_is_printed_and_counted_but_does_not_fail_the_host
    source = File.read(DOCTOR)
    assert_match(/#\{unmeasured_checks\.size\} checks measured nothing/, source,
                 "unmeasured checks are not named in the output")
    assert_match(/def ok = state != :fail/, source,
                 "unmeasured must not count as a failure for the exit code")
  end

  # content-dedup passes whatever it finds, so its crash path must not be the
  # one way an advisory check fails the host's exit code.
  def test_advisory_check_crash_is_unmeasured_not_a_failure
    definition = File.read(DOCTOR)[/^def check_content_dedup.*?^end/m]
    refute_nil definition, "check_content_dedup moved; this test runs its definition"
    host = Object.new
    host.singleton_class.const_set(:Check, Struct.new(:name, :state, :detail, keyword_init: true))
    host.singleton_class.const_set(:ROOT, ROOT)
    host.singleton_class.class_eval(definition)
    require "fix/content_dedup_scan"

    check = Master::Fix::ContentDedupScan.stub(:scan, ->(**) { raise IOError, "disk went away" }) do
      host.check_content_dedup
    end

    assert_equal :unmeasured, check.state, "the advisory content-dedup check can fail the host"
    assert_includes check.detail, "disk went away"
  end

  # Every construction goes through the three-state struct. A stray `ok:` is an
  # ArgumentError at runtime, which is how this was found: doctor crashed on
  # its first check after the struct changed.
  def test_empty_quota_ledger_is_unmeasured
    check = model_quota_check(models: {}, exhausted: [], provider: nil)

    assert_equal :unmeasured, check.state
    assert_match(/no quota observations/, check.detail)
  end

  def test_fresh_provider_quota_is_measured_without_local_lane_history
    check = model_quota_check(
      models: {}, exhausted: [],
      provider: { fresh: true, remaining: 12 },
    )

    assert_equal :pass, check.state
    assert_match(/12 remaining/, check.detail)
  end

  def test_confirmed_provider_exhaustion_fails_without_local_lane_history
    check = model_quota_check(
      models: {}, exhausted: [],
      provider: { fresh: true, remaining: 0 },
    )

    assert_equal :fail, check.state
    assert_match(/openrouter:free/, check.detail)
  end

  def test_doctor_does_not_swallow_master_boot_errors
    source = File.read(DOCTOR)
    refute_match(/require "master" rescue nil/, source)
    assert_match(/require "master"\n/, source)
  end

  def model_quota_check(snapshot)
    require "io/model_quota"
    definition = File.read(DOCTOR)[/^def check_model_quota.*?^end/m]
    refute_nil definition, "check_model_quota moved; this test exercises the measured verdict"
    host = Object.new
    host.singleton_class.const_set(
      :Check, Struct.new(:name, :state, :detail, keyword_init: true),
    )
    host.singleton_class.class_eval(definition)
    Master::Io::ModelQuota.stub(:snapshot, ->(**) { snapshot }) { host.check_model_quota }
  end

  def test_keyless_probe_is_a_real_anonymous_completion_probe
    source = File.read(DOCTOR)
    definition = source[/^def check_keyless_completion.*?^end/m]
    refute_nil definition
    assert_includes definition, 'ENV["MASTER_FREE_ONLY"] = "1"'
    assert_includes definition, "Master::Soul.load!"
    assert_includes definition, "agent.ask_once"
    assert_includes definition, "failover: false"
    assert_includes definition, "Master::Io::LaneSelection.reset_hosted_resolver!"
  end

  def test_no_check_is_constructed_with_a_boolean
    code = File.read(DOCTOR).lines.reject { |line| line.strip.start_with?("#") }.join
    refute_match(/Check\.new\([^)]*\bok:/, code, "a Check is still built with ok:")
  end

  # The 2026-11-08 transcript left one open row: the terminal printed
  # "voice0: audio playback failed - /usr/bin/afplay" and no sound reached the
  # operator, while tts-socket kept answering "local speech/playback ready".
  # check_voice_utterance is the row's instrument, so its contract is pinned
  # here: a host that cannot hear measures nothing, a host that hears gets a
  # receipt naming the player and the engine, and a degraded chain still names
  # its first failure instead of passing silently.
  def voice_utterance_host
    definition = File.read(DOCTOR)[/^def check_voice_utterance.*?^end/m]
    refute_nil definition, "check_voice_utterance moved; this test runs its definition"
    host = Object.new
    host.singleton_class.const_set(:Check, Struct.new(:name, :state, :detail, keyword_init: true))
    host.singleton_class.const_set(:ROOT, ROOT)
    host.singleton_class.class_eval(definition)
    host
  end

  def with_voice_stubs(playback_available:, speak_now:, player: nil,
                       speech_engine: nil, speech_error: nil, playback_error: nil)
    require "master"
    playback = Master::Voice::Playback
    speech = Master::Voice::Speech
    # The check refuses to measure through a pipe, and a test worker's stdout is
    # a pipe - lend the process a terminal for the duration of the stubs.
    $stdout.singleton_class.send(:alias_method, :test_real_tty?, :tty?)
    $stdout.singleton_class.send(:define_method, :tty?) { true }
    playback.stub(:available?, playback_available) do
      playback.stub(:speak_now, speak_now) do
        playback.stub(:player, player) do
          playback.stub(:last_error, playback_error) do
            speech.stub(:last_engine, speech_engine) do
              speech.stub(:last_error, speech_error) do
                yield
              end
            end
          end
        end
      end
    end
  ensure
    $stdout.singleton_class.send(:remove_method, :tty?)
    $stdout.singleton_class.send(:remove_method, :test_real_tty?)
  end

  def test_voice_utterance_measures_nothing_where_no_ear_exists
    host = voice_utterance_host
    check = with_voice_stubs(playback_available: false, speak_now: nil) { host.check_voice_utterance }

    assert_equal :unmeasured, check.state
    assert_includes check.detail, "no audio output on this host"
    assert_includes check.detail, "INCONCLUSIVE by construction"
  end

  def test_voice_utterance_measures_nothing_behind_a_pipe
    host = voice_utterance_host
    check = with_voice_stubs(playback_available: true, speak_now: nil) do
      ENV["CI"] = "1"
      host.check_voice_utterance
    ensure
      ENV["CI"] = nil
    end

    assert_equal :unmeasured, check.state
    assert_includes check.detail, "cannot be verified from a pipe or CI run"
  end

  def test_voice_utterance_receipt_names_the_player_and_the_engine
    host = voice_utterance_host
    check = with_voice_stubs(
      playback_available: true, speak_now: true,
      player: ["/usr/bin/afplay", []], speech_engine: "edge", speech_error: nil
    ) { host.check_voice_utterance }

    assert_equal :pass, check.state
    assert_includes check.detail, "player=/usr/bin/afplay, engine=edge, utterance played"
    refute_includes check.detail, "degraded"
  end

  def test_a_degraded_chain_that_still_reached_the_ear_passes_with_its_first_failure
    host = voice_utterance_host
    failure = "neural voices unreachable - speech falls back to the OS voices or stays silent"
    check = with_voice_stubs(
      playback_available: true, speak_now: true,
      player: ["/usr/bin/afplay", []], speech_engine: "say", speech_error: failure
    ) { host.check_voice_utterance }

    assert_equal :pass, check.state
    assert_includes check.detail, "engine=say"
    assert_includes check.detail, "degraded chain, first failure: #{failure}"
  end

  def test_voice_utterance_fails_when_no_sound_reached_the_ear
    host = voice_utterance_host
    failure = "neural voices unreachable - speech falls back to the OS voices or stays silent"
    check = with_voice_stubs(
      playback_available: true, speak_now: false,
      player: nil, speech_engine: nil, speech_error: failure
    ) { host.check_voice_utterance }

    assert_equal :fail, check.state
    assert_includes check.detail, "no sound reached the ear"
    assert_includes check.detail, failure
  end
end
