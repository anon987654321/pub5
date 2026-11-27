# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestDeviceAgent < Minitest::Test
  class FakeCognition
    attr_reader :ticks

    def initialize
      @ticks = 0
    end

    def tick!
      @ticks += 1
    end
  end

  class FakeStanding
    attr_reader :owners

    def initialize
      @owners = []
    end

    def run_due!(owner:)
      @owners << owner
      []
    end
  end

  def test_status_is_unpaired_before_local_owner_claim
    Dir.mktmpdir("device-agent") do |root|
      status = Master::Device::Agent.status(root:)
      refute status[:paired]
      assert_equal "", status[:owner_subject]
    end
  end

  def test_claim_owner_persists_subject_and_pairs_current_session
    Dir.mktmpdir("device-agent") do |root|
      result = Master::Device::Agent.claim_owner!(root:, label: "Alex")
      status = Master::Device::Agent.status(root:)

      refute_empty result[:subject]
      refute result.key?(:token)
      assert_equal result[:subject], status[:owner_subject]
      assert_equal "Alex", status[:owner_label]
      assert_equal true, Fiber[:master_paired]
      assert_equal result[:subject], Fiber[:master_pair_subject]
    ensure
      Fiber[:master_paired] = nil
      Fiber[:master_pair_subject] = nil
    end
  end

  def test_claim_owner_refuses_a_second_owner
    Dir.mktmpdir("device-agent") do |root|
      Master::Device::Agent.send(:save_state, root, "owner_subject" => "owner123")
      error = assert_raises(RuntimeError) { Master::Device::Agent.claim_owner!(root:, label: "Other") }
      assert_match(/already paired/, error.message)
    end
  end

  def test_release_owner_clears_identity_but_keeps_personal_workspace
    Dir.mktmpdir("device-agent") do |root|
      result = Master::Device::Agent.claim_owner!(root:, label: "Alex")
      workspace = Master::Ground::PersonalWorkspace.dir_for(result[:subject], root:)
      assert File.directory?(workspace)

      released = Master::Device::Agent.release_owner!(root:)
      assert_equal result[:subject], released
      refute Master::Device::Agent.paired?(root:)
      assert File.directory?(workspace)
    ensure
      Fiber[:master_paired] = nil
      Fiber[:master_pair_subject] = nil
    end
  end

  def test_tick_persists_runtime_state_without_running_personal_orders
    Dir.mktmpdir("device-agent") do |root|
      cognition = FakeCognition.new
      standing = FakeStanding.new
      agent = Master::Device::Agent.new(root:, bus: nil, cognition:, standing:)
      agent.tick!

      assert_equal 1, cognition.ticks
      assert_empty standing.owners
      status = Master::Device::Agent.status(root:)
      refute_nil status[:last_tick_at]
      refute status[:paired]
    end
  end

  def test_tick_scopes_standing_orders_to_persisted_owner
    Dir.mktmpdir("device-agent") do |root|
      Master::Device::Agent.send(:save_state, root, "owner_subject" => "owner123", "owner_label" => "owner")
      standing = FakeStanding.new
      agent = Master::Device::Agent.new(root:, bus: nil, cognition: FakeCognition.new, standing:)
      agent.tick!

      assert_equal ["owner123"], standing.owners
    end
  end
end

require_relative "test_helper"
require "tempfile"

class TestDeviceAudio < Minitest::Test
  Audio = Master::Device::Audio

  def setup
    @old_android = Master::Device.method(:android?)
    @old_executable = Audio.method(:executable?)
    @old_run = Audio.method(:run)
  end

  def teardown
    Master::Device.define_singleton_method(:android?, &@old_android)
    Audio.define_singleton_method(:executable?, &@old_executable)
    Audio.define_singleton_method(:run, &@old_run)
  end

  def test_android_audio_availability_is_capability_based
    Master::Device.define_singleton_method(:android?) { true }
    Audio.define_singleton_method(:executable?) { |command| command == Audio::TTS_COMMAND }

    assert Audio.tts_available?
    refute Audio.media_player_available?
    assert Audio.available?
  end

  def test_speak_uses_the_canonical_termux_tts_command
    calls = []
    Master::Device.define_singleton_method(:android?) { true }
    Audio.define_singleton_method(:executable?) { |command| command == Audio::TTS_COMMAND }
    Audio.define_singleton_method(:run) { |*argv| calls << argv; true }

    assert Audio.speak("hello")
    assert_equal [[Audio::TTS_COMMAND, "-s", "MUSIC", "hello"]], calls
  end

  def test_media_playback_and_stop_use_the_same_boundary
    calls = []
    Master::Device.define_singleton_method(:android?) { true }
    Audio.define_singleton_method(:executable?) { |command| command == Audio::MEDIA_PLAYER }
    Audio.define_singleton_method(:run) { |*argv| calls << argv; true }

    Tempfile.create(["master-audio", ".mp3"]) do |file|
      file.write("audio")
      file.flush

      assert Audio.play(file.path)
      assert Audio.stop
      assert_equal [
        [Audio::MEDIA_PLAYER, "play", file.path],
        [Audio::MEDIA_PLAYER, "stop"],
      ], calls
    end
  end
end

require_relative "test_helper"

# The first boot on a phone says what is present and what is missing, with the
# fix for each. Nothing here touches the real home: the mark, the env file,
# PATH and git are all stubbed.
class TestDeviceOnboarding < Minitest::Test
  Onboarding = Master::Device::Onboarding
  KEY = "k" * 40

  def setup
    @dir = Dir.mktmpdir
    @mark = File.join(@dir, "state", "onboarded")
    @env_file = File.join(@dir, "config", "master", "env")
    @out = StringIO.new
    @present = []
  end

  def teardown = FileUtils.rm_rf(@dir)

  def onboarding(env: {}, android: true, identity: "")
    Onboarding.new(env:, out: @out, android:, mark: @mark, env_file: @env_file,
                   which: ->(cmd) { @present.include?(cmd) }, root: "/data/data/com.termux/files/home/pub5/MASTER",
                   git: ->(_key) { identity })
  end

  def test_a_first_run_is_detected_once_and_marks_through_the_shared_writer
    first = onboarding
    calls = []
    writer = Master::Io::AtomicWrite.method(:write_atomic)
    instrumented = lambda do |path, content, **options|
      calls << [path, content, options]
      writer.call(path, content, **options)
    end

    assert first.first_run?
    Master::Io::AtomicWrite.stub(:write_atomic, instrumented) { first.run }
    refute onboarding.first_run?
    assert File.exist?(@mark)
    assert_equal 1, calls.length
    assert_equal @mark, calls.first.first
  end

  def test_the_phone_checklist_names_each_missing_piece_with_its_fix
    Master::Device.stub(:android?, true) do
      Onboarding.new(env: {}, out: @out, mark: @mark, env_file: @env_file, which: ->(_cmd) { false },
                     git: ->(_key) { "" }).run
    end
    text = @out.string
    assert_match(/^onboard0: first run on this phone$/, text)
    assert_match(/^env0: created /, text)
    assert_match(/^build0: .*pkg install build-essential$/, text)
    assert_match(/^termux0: .*install the Termux:API app, then pkg install termux-api$/, text)
    assert_match(/^model0: no key.*set OPENROUTER_API_KEY in .*env, or pkg install ollama/, text)
    assert_match(/^git0: .*git config --global user.name/, text)
    assert_match(/^ear0: packages /, text)
    assert_match(%r{^checkout0: checkout at }, text)
  end

  def test_a_host_that_is_not_a_phone_skips_the_termux_checks
    onboarding(android: false, identity: "dev").run
    assert_match(/^onboard0: first run on this host$/, @out.string)
    refute_match(/^(build|termux|sqlite|ear)0:/, @out.string)
  end

  def test_a_later_boot_prints_only_what_is_still_missing
    onboarding.run
    @out = StringIO.new
    @present.concat(%w[clang make pkg-config])
    onboarding.run
    lines = @out.string.lines.map { |line| line.split(":").first }
    # The fixture phone has no owner yet, so the pairing hint is still missing too.
    assert_equal %w[android0 termux0 git0], lines
  end

  def test_a_checkout_on_shared_storage_is_named
    check = Onboarding.new(env: {}, out: @out, android: true, mark: @mark, env_file: @env_file,
                           which: ->(_cmd) { false }, root: "/storage/emulated/0/pub5/MASTER", git: ->(_key) { "" })
                      .checks.find { |candidate| candidate.name == :checkout }
    refute check.ok
    assert_includes check.says, "~/pub5"
  end

  def test_the_env_template_is_written_once_with_no_key
    assert onboarding.ensure_env_file
    text = File.read(@env_file)
    assert_equal 0o600, File.stat(@env_file).mode & 0o777
    assert(text.lines.all? { |line| line.start_with?("#") })
    File.write(@env_file, "OPENROUTER_API_KEY=#{KEY}\n")
    refute onboarding.ensure_env_file
    assert_equal "OPENROUTER_API_KEY=#{KEY}\n", File.read(@env_file)
  end

  def test_one_key_picks_its_lane
    assert_equal %w[gemini GEMINI_API_KEY], onboarding(env: { "GEMINI_API_KEY" => KEY }).lane
    assert_equal %w[replicate REPLICATE_API_TOKEN], onboarding(env: { "REPLICATE_API_TOKEN" => KEY }).lane
    assert_equal %w[openrouter OPENROUTER_API_KEY],
                 onboarding(env: { "GEMINI_API_KEY" => KEY, "OPENROUTER_API_KEY" => KEY }).lane
  end

  def test_no_key_falls_to_ollama_then_the_keyless_tier
    assert_equal ["llm7", nil], onboarding(env: { "OPENROUTER_API_KEY" => "short" }).lane
    @present << "ollama"
    assert_equal ["ollama", nil], onboarding.lane
  end

  def test_it_stays_quiet_without_a_terminal_or_under_proof
    assert_nil Onboarding.run!(env: {}, out: @out, tty: false)
    assert_nil Onboarding.run!(env: { "MASTER_IN_PROOF" => "1" }, out: @out, tty: true)
    assert_empty @out.string
  end

  def test_missing_gems_reads_the_lockfile_and_skips_git_sources
    lock = File.join(@dir, "Gemfile.lock")
    File.write(lock, "GEM\n  specs:\n\nDEPENDENCIES\n  minitest (>= 5.25)\n  no_such_gem_here (~> 1.0)\n  " \
                     "some_git_gem!\n\nBUNDLED WITH\n  4.0.5\n")
    assert_equal ["no_such_gem_here"], Onboarding.missing_gems(lock)
  end
end

require_relative "test_helper"
require "tmpdir"

class TestDeviceOwnerProfile < Minitest::Test
  Profile = Master::Device::OwnerProfile
  SUBJECT = "abc123"

  # The profile is personal memory, so it is written only after its owner grants that scope.
  def with_granted_root
    Dir.mktmpdir("owner-profile") do |root|
      purpose = Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE
      permissions = Master::Ground::PersonalPermissions.new(root:)
      permissions.grant(scope: "personal_memory", subject: SUBJECT, confirmed_by: "local owner", purpose:)

      yield root
    end
  end

  def test_nothing_is_written_before_personal_memory_is_granted
    denied = Master::Ground::PersonalWorkspace::PermissionDenied

    Dir.mktmpdir("owner-profile") do |root|
      assert_raises(denied) { Profile.set(root:, subject: SUBJECT, name: "Alex") }
      assert_empty Profile.values(root:, subject: SUBJECT)
      assert_includes Profile.onboarding_prompt(root:, subject: SUBJECT), "/privacy grant personal_memory"
    end
  end

  def test_set_reads_back_only_declared_profile_fields
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, name: "Alex", language: "English", timezone: "Europe/Oslo",
                  ignored: "secret", interests: "music, code")

      values = Profile.values(root:, subject: SUBJECT)
      assert_equal "Alex", values["name"]
      assert_equal "English", values["language"]
      assert_equal "Europe/Oslo", values["timezone"]
      assert_equal "music, code", values["interests"]
      refute values.key?("ignored")
    end
  end

  def test_forget_removes_one_field_without_touching_the_others
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, name: "Alex", language: "English")
      Profile.forget(root:, subject: SUBJECT, key: "language")

      values = Profile.values(root:, subject: SUBJECT)
      assert_equal "Alex", values["name"]
      refute values.key?("language")
    end
  end

  def test_pet_name_customizes_the_wake_greeting
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, pet_name: "Mochi")

      assert_includes Profile.wake_greeting(root:, subject: SUBJECT), "Mochi"
    end
  end

  def test_onboarding_prompt_reports_missing_fields
    with_granted_root do |root|
      prompt = Profile.onboarding_prompt(root:, subject: SUBJECT)
      assert_match(/Name/, prompt)
      assert_match(/Language/, prompt)
    end
  end

  def test_onboarding_prompt_closes_after_all_fields_are_set
    with_granted_root do |root|
      Profile.set(root:, subject: SUBJECT, **Profile::KEYS.to_h { |key| [key.to_sym, "x"] })

      assert_equal "owner0: profile complete", Profile.onboarding_prompt(root:, subject: SUBJECT)
    end
  end
end

require_relative "test_helper"

class TestDevicePerception < Minitest::Test
  def test_sensor_name_discovery_accepts_arrays_and_hashes
    bus = Object.new
    perception = Master::Device::Perception.new(bus:, interval: 1)
    names = perception.send(:discover_sensor_names, %w[Accelerometer Light])
    assert_equal %w[Accelerometer Light], names
    names = perception.send(:discover_sensor_names, { "Accelerometer" => {}, "Light" => {} })
    assert_equal %w[Accelerometer Light], names
  end

  def test_publish_adds_android_source
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, payload| events << [event, payload] }
    perception = Master::Device::Perception.new(bus:, interval: 1)
    perception.send(:publish, "device:test", value: 1)
    assert_equal ["device:test", { value: 1, source: "android" }], events.first
  end
end

require_relative "test_helper"

# A new Termux install sets up the face's ear by itself. Every command here is
# stubbed: a test never runs pkg, git, cmake or curl.
class TestDeviceSetup < Minitest::Test
  Setup = Master::Device::Setup

  def setup
    @dir = Dir.mktmpdir
    @state = File.join(@dir, "face_setup.json")
    @ran = []
    @present = []
    @now = 1_000_000
    @out = StringIO.new
  end

  def teardown = FileUtils.rm_rf(@dir)

  # installs: which argv puts which command on PATH when it succeeds.
  def setup_with(fails: [], installs: {})
    Setup.new(env: { "PREFIX" => "/data/data/com.termux/files/usr" }, which: ->(cmd) { @present.include?(cmd) },
              clock: -> { @now }, state_path: @state, out: @out,
              sh: lambda { |argv|
                @ran << argv
                next false if fails.any? { |word| argv.include?(word) }

                @present.concat(Array(installs[argv.first(4)]))
                true
              })
  end

  def test_the_plan_names_the_packages_the_build_and_the_model
    steps = setup_with.plan
    assert_equal %i[packages whisper model], steps.map(&:name)
    assert_equal [%w[pkg install -y termux-api sox ffmpeg pulseaudio]], steps[0].tries.first
    assert_equal %w[termux-speech-to-text termux-tts-speak termux-media-player sox ffmpeg parec], Setup::PACKAGE_COMMANDS
    pkg_try, build = steps[1].tries
    assert_equal [%w[pkg install -y x11-repo], %w[pkg install -y whisper-cpp]], pkg_try
    assert_equal %w[pkg install -y git cmake clang make curl], build[0]
    assert_includes build.map(&:first), "cmake"
    assert_equal "/data/data/com.termux/files/usr/bin/whisper-cli", build.last.last
    assert_equal "curl", steps[2].tries.first[1].first
    assert steps[2].tries.first[1].last.end_with?("ggml-base.bin")
  end

  def test_nothing_runs_when_the_ear_is_in_place
    @present.concat(%w[termux-speech-to-text termux-tts-speak termux-media-player sox ffmpeg parec whisper-cli])
    setup = setup_with
    model = File.join(@dir, "ggml-base.bin")
    File.open(model, "wb") { |f| f.truncate(Master::CLI::Face::Transcriber::MIN_MODEL_BYTES) }
    setup.define_singleton_method(:model_path) { model }
    setup.run
    assert_empty @ran
    assert_equal "done", JSON.parse(File.read(@state)).dig("whisper", "state")
  end

  def test_whisper_builds_from_source_when_pkg_lacks_it
    @present.concat(%w[termux-speech-to-text termux-tts-speak termux-media-player sox ffmpeg parec])
    setup = setup_with(fails: ["whisper-cpp"], installs: { ["install", "-m", "755", File.join(Setup::SOURCE, "build", "bin", "whisper-cli")] => "whisper-cli" })
    setup.define_singleton_method(:plan) { super().select { |step| step.name == :whisper } }
    setup.run
    assert_equal %w[pkg install -y whisper-cpp], @ran[1]
    assert_equal "install", @ran.last.first
    assert_match(/ear0: whisper ready/, @out.string)
  end

  def test_a_finished_step_is_not_repeated_on_the_next_boot
    installs = { %w[pkg install -y termux-api] => %w[termux-speech-to-text termux-tts-speak termux-media-player sox ffmpeg parec] }
    setup = setup_with(installs:)
    setup.define_singleton_method(:plan) { super().first(1) }
    setup.run
    assert_equal 1, @ran.size
    setup.run
    assert_equal 1, @ran.size, "the next boot ran pkg again"
  end

  def test_a_failed_build_waits_and_backs_off
    setup = setup_with(fails: %w[whisper-cpp cmake])
    setup.define_singleton_method(:plan) { super().select { |step| step.name == :whisper } }
    setup.run
    tries = @ran.size
    entry = JSON.parse(File.read(@state))["whisper"]
    assert_equal 1, entry["failures"]
    assert_equal @now + 3_600, entry["retry_at"]

    setup.run
    assert_equal tries, @ran.size, "a failed build retried at once"
    assert_match(/whisper waits until/, @out.string)

    @now += 3_600
    setup.run
    assert_equal @now + 7_200, JSON.parse(File.read(@state)).dig("whisper", "retry_at"), "the wait did not double"
  end

  def test_the_build_stops_after_five_failures
    setup = setup_with(fails: %w[whisper-cpp cmake])
    setup.define_singleton_method(:plan) { super().select { |step| step.name == :whisper } }
    File.write(@state, JSON.generate("whisper" => { "state" => "failed", "failures" => 5, "retry_at" => 0 }))
    setup.run
    assert_empty @ran
    assert_match(/stopped after 5 failures/, @out.string)
  end

  def test_it_never_starts_under_test_or_off_a_phone
    phone = Struct.new(:android?).new(true)
    assert_nil Setup.start!(device: phone, env: { "MASTER_IN_PROOF" => "1" })
    assert_nil Setup.start!(device: phone, env: { "MASTER_FACE_SETUP" => "0" })
    assert_nil Setup.start!(device: Struct.new(:android?).new(false), env: {})
  end
end

require_relative "test_helper"

class TestDeviceWakeDefaults < Minitest::Test
  def test_device_wake_does_not_disable_cli_voice
    path = File.expand_path("../bin/device-wake", __dir__)
    source = File.read(path)

    refute_includes source, 'ENV["MASTER_CLI_SPEAK"] = "0"'
    assert_includes source, 'ENV["MASTER_SKIP_TTS"] = "0"'
    assert_includes source, 'ENV["MASTER_CLI_SPEAK"] = "1"'
  end
end

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/device/wake_signal"

class TestDeviceWakeSignal < Minitest::Test
  def test_publish_uses_the_shared_private_atomic_writer
    Dir.mktmpdir do |root|
      calls = []
      writer = Master::Io::AtomicWrite.method(:write_atomic)
      instrumented = lambda do |path, content, **options|
        calls << [path, content, options]
        writer.call(path, content, **options)
      end
      event = nil
      Master::Io::AtomicWrite.stub(:write_atomic, instrumented) do
        event = Master::Device::WakeSignal.publish(root:, phrase: "hey mochi", at: 123.45)
      end

      assert_equal 1, calls.length
      assert_equal File.join(root, Master::Device::WakeSignal::PATH), calls.first.first
      assert_equal 0o600, calls.first.last.fetch(:mode)
      assert_equal event[:id], Master::Device::WakeSignal.read(root:)[:id]
      assert_equal 0o600, File.stat(calls.first.first).mode & 0o777
      assert_empty Dir.children(File.join(root, ".master")).grep(/master_atomic|wake-event-/)
    end
  end

  def test_missing_signal_is_empty
    Dir.mktmpdir do |root|
      assert_nil Master::Device::WakeSignal.read(root:)
    end
  end
end

require_relative "test_helper"
require "tmpdir"

class TestDeviceWakeWord < Minitest::Test
  def test_enable_normalizes_phrases
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true }, permissions: granted_permissions(root))
      wake.enable!(phrases: ["Hey MASTER", " hey master "])

      Master::Device.stub(:android?, true) do
        Master::Device.stub(:termux?, true) do
          assert wake.enabled?
        end
      end
      assert_equal ["hey master"], wake.phrases
    end
  end

  def test_match_accepts_a_phrase_inside_transcription
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true }, permissions: granted_permissions(root))
      wake.enable!(phrases: ["hey mochi"])

      assert_equal "hey mochi", wake.send(:match, "Hey Mochi, are you there?")
      assert_nil wake.send(:match, "hello there")
    end
  end

  # The consent law gates the wake word: grant both scopes through the real
  # permission store, with the exact purposes the listener checks.
  def granted_permissions(root)
    permissions = Master::Ground::PersonalPermissions.new(root:)
    permissions.grant(
      scope: "microphone", confirmed_by: "test",
      purpose: Master::Ground::PersonalPermissions::MICROPHONE_PURPOSE,
    )
    permissions.grant(
      scope: "speech_recognition", confirmed_by: "test",
      purpose: Master::Ground::PersonalPermissions::SPEECH_RECOGNITION_PURPOSE,
    )
    permissions
  end

  def test_default_command_probe_uses_the_shared_path_resolver
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:)
      calls = []
      resolver = lambda do |name|
        calls << name
        name == "termux-microphone-record"
      end

      Master::Mobile::Env.stub(:on_path?, resolver) do
        error = assert_raises(RuntimeError) { wake.run_forever }
        assert_match(/whisper-cli/, error.message)
      end

      assert_equal %w[termux-microphone-record whisper-cli], calls
    end
  end

  def test_disabled_listener_does_not_require_microphone
    Dir.mktmpdir("wake-word") do |root|
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true })

      wake.send(:write_state, "enabled" => false)
      # The listener checks tool availability once, then sleeps without opening
      # the microphone while disabled.
      wake = Master::Device::WakeWord.new(root:, which: ->(_cmd) { true }, sleeper: ->(_seconds) { raise "stop" })
      assert_raises(RuntimeError) { wake.run_forever }
    end
  end
end
