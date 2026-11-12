# frozen_string_literal: true

require "fileutils"
require_relative "minitest_helper"
require "open3"
require "tmpdir"
require_relative "../output_paths"
require "digest"
require_relative "../dilla/dilla"

# The whole suite stays under four minutes: every render here is one or two
# bars, and the analyzer run gets a two-bar fixture. Full-catalogue renders
# are a session activity, not a test.

class TestDillaCliContract < Minitest::Test
  def ruby
    RbConfig.ruby
  end

  def dilla
    File.expand_path("../dilla/dilla.rb", __dir__)
  end

  def run_dilla(*argv, chdir: File.dirname(dilla), env: {})
    out, err, status = Open3.capture3(env, ruby, dilla, *argv, chdir: chdir)
    [out, err, status]
  end

  def test_list_matches_the_format_master_parses
    out, err, status = run_dilla("--list")
    assert status.success?, "dilla --list failed: #{err}"
    lines = out.lines
    assert lines.first&.start_with?("Progressions:"), "menu must open with Progressions:"
    numbered = lines.drop_while { |l| !l.start_with?("Progressions:") }.drop(1)
                    .take_while { |l| !l.strip.empty? }
                    .filter_map { |l| l[/\A\s+(\d+)\s/, 1] }
    assert numbered.length >= 8, "engine plus recovered progressions expected"
    assert_equal (1..numbered.length).map(&:to_s), numbered, "progression numbering is dense"
    drums = lines.find { |l| l.start_with?("Drum patterns:") }
    assert drums, "Drum patterns: line missing"
    assert_includes drums, "dilla_shadow_full"
    assert_includes drums, "dusty_laid_back"
    profiles = lines.find { |l| l.start_with?("Groove profiles:") }
    assert profiles, "Groove profiles: line missing"
    assert_includes profiles, "dilla_shadow"
  end

  def test_help_lists_the_reference_pipeline
    out, _err, status = run_dilla("--help")
    assert status.success?
    assert_includes out, "reference"
    assert_includes out, "output-path"
  end

  def test_output_path_answers_the_master_contract
    Dir.mktmpdir do |dir|
      # MASTER sends its clock as the optional third argument; the flat render
      # layout carries it without steering the path.
      out, err, status = run_dilla("output-path", "dilla-render-directory",
                                   "2026-11-01T09:00:00Z",
                                   env: { "DILLA_OUTPUT_DIR" => File.join(dir, "renders") })
      assert status.success?, err
      assert_equal File.join(File.realpath(dir), "renders"), out.strip

      out, _e, status = run_dilla("output-path", "reference-root", env: { "XDG_DATA_HOME" => dir })
      assert status.success?
      # The reference root resolves symlinks; macOS's /var is /private/var.
      assert_equal File.join(File.realpath(dir), "dilla-references"), out.strip
    end
  end

  def test_output_overrides_cannot_write_inside_the_checkout
    root = Studio::OutputPaths::REPOSITORY_ROOT
    {
      "DILLA_OUTPUT_DIR" => -> { Studio::OutputPaths.dilla_render_directory },
      "POSTPRO_OUTPUT_DIR" => -> { Studio::OutputPaths.render_directory }
    }.each do |name, resolve|
      previous = ENV[name]
      begin
        ENV[name] = File.join(root, "STUDIO", "unapproved-renders")
        error = assert_raises(ArgumentError, name) { resolve.call }
        assert_match(/resolves inside the checkout/, error.message)
      ensure
        previous ? ENV[name] = previous : ENV.delete(name)
      end
    end
  end

  def test_external_output_overrides_remain_supported
    Dir.mktmpdir("studio-external-output-") do |directory|
      {
        "DILLA_OUTPUT_DIR" => -> { Studio::OutputPaths.dilla_render_directory },
        "POSTPRO_OUTPUT_DIR" => -> { Studio::OutputPaths.render_directory }
      }.each do |name, resolve|
        previous = ENV[name]
        begin
          target = File.join(File.realpath(directory), name)
          ENV[name] = target
          # The override comes back resolved through the same canonical path.
          assert_equal target, resolve.call
        ensure
          previous ? ENV[name] = previous : ENV.delete(name)
        end
      end
    end
  end

  def test_output_override_symlinks_are_resolved_before_the_checkout_check
    root = Studio::OutputPaths::REPOSITORY_ROOT
    Dir.mktmpdir("studio-output-link-") do |directory|
      link = File.join(directory, "renders")
      File.symlink(File.join(root, "STUDIO", "dilla"), link)
      previous = ENV["DILLA_OUTPUT_DIR"]
      begin
        ENV["DILLA_OUTPUT_DIR"] = link
        error = assert_raises(ArgumentError) { Studio::OutputPaths.dilla_render_directory }
        assert_match(/resolves inside the checkout/, error.message)
      ensure
        previous ? ENV["DILLA_OUTPUT_DIR"] = previous : ENV.delete("DILLA_OUTPUT_DIR")
      end
    end
  end

  def test_unknown_flags_are_rejected
    _out, err, status = run_dilla("--frobnicate")
    refute status.success?
    assert_match(/unknown flag/, err)
  end
end

class TestDillaTheory < Minitest::Test
  def test_every_progression_chord_parses
    Dilla.progressions.each do |prog|
      prog.fetch("chords").each do |symbol|
        parsed = Dilla::ChordParser.parse(symbol, Dilla.theory)
        assert parsed[:root].between?(0, 11), "#{symbol}: root out of range"
        refute_empty parsed[:intervals], "#{symbol}: no intervals"
      rescue ArgumentError => e
        flunk "#{prog['id']}: #{e.message}"
      end
    end
  end

  def test_extended_and_slash_chords_parse
    {
      "Ab13" => [0, 4, 10, 14, 21],
      "Dbmaj9#11" => [0, 4, 11, 14, 18],
      "C7b9" => [0, 4, 10, 13],
      "D7alt" => [0, 4, 10, 15, 19],
      "Gsus4" => [0, 5, 7],
      "Bb/E" => [0, 4, 7]
    }.each do |symbol, _expected_shape|
      parsed = Dilla::ChordParser.parse(symbol, Dilla.theory)
      refute_nil parsed
    end
  end

  def test_unknown_chord_qualities_and_invalid_slash_bass_are_rejected
    error = assert_raises(ArgumentError) do
      Dilla::ChordParser.parse("Cmajorr", Dilla.theory)
    end
    assert_match(/unknown chord quality/, error.message)

    error = assert_raises(ArgumentError) do
      Dilla::ChordParser.parse("C7/H", Dilla.theory)
    end
    assert_match(/unknown slash-bass note/, error.message)
  end

  def test_slash_bass_pitch_class_is_read
    parsed = Dilla::ChordParser.parse("Bb/E", Dilla.theory)
    assert_equal 4, parsed[:bass]
  end

  def test_modifiers_replace_the_natural_interval_they_alter
    {
      "C7b5" => [0, 4, 6, 10],
      "C7#5" => [0, 4, 8, 10],
      "C9b9" => [0, 4, 7, 10, 13],
      "C11#11" => [0, 4, 7, 10, 14, 18],
      "C13b13" => [0, 4, 10, 14, 20],
      "D7alt" => [0, 4, 10, 15, 19]
    }.each do |symbol, expected|
      assert_equal expected, Dilla::ChordParser.parse(symbol, Dilla.theory)[:intervals], symbol
    end
  end

  def test_historical_chart_spellings_and_slash_extensions_parse
    expected = {
      "Ebm7fil" => ["m9", [0, 3, 7, 10, 14]],
      "E7climax" => ["9", [0, 4, 7, 10, 14]],
      "Cm11nc" => ["m11", [0, 3, 7, 10, 14, 17]],
      "A7nc" => ["7", [0, 4, 7, 10]],
      "Dmaj9nc" => ["maj9", [0, 4, 7, 11, 14]],
      "AbMaj13s11" => ["maj13", [0, 4, 7, 11, 14, 18, 21]],
      "Asus9" => ["sus9", [0, 5, 7, 14]]
    }
    expected.each do |symbol, (quality, intervals)|
      parsed = Dilla::ChordParser.parse(symbol, Dilla.theory)
      assert_equal quality, parsed[:quality], symbol
      assert_equal intervals, parsed[:intervals], symbol
    end

    slash = Dilla::ChordParser.parse("D6/9/F#", Dilla.theory)
    assert_equal "6/9", slash[:quality]
    assert_equal 6, slash[:bass]
    assert_equal 7, Dilla::ChordParser.parse("DMaj7overG", Dilla.theory)[:bass]
    assert_nil Dilla::ChordParser.parse("C6/9", Dilla.theory)[:bass]
  end

  def test_voicer_keeps_inner_voices_close_and_top_voice_high
    voicer = Dilla::Voicer.new(Dilla.theory)
    rng = Dilla::Rng.new(12)
    chords = %w[Fm9 Ab13 Dbmaj7#11 C7b9].map { |s| Dilla::ChordParser.parse(s, Dilla.theory) }
    voiced = voicer.voice(chords, rng)
    voiced.each_cons(2) do |a, b|
      b.each do |note|
        nearest = a.map { |n| (n - note).abs }.min
        assert nearest <= 7, "inner voice jumped #{nearest} semitones: #{a.inspect} -> #{b.inspect}"
      end
    end
    voiced.each do |voicing|
      assert voicing.max.between?(67, 96), "top voice out of register: #{voicing.inspect}"
    end
  end

  def test_voice_leading_requires_distinct_predecessors
    voicer = Dilla::Voicer.new(Dilla.theory)

    # All three new notes are individually within a fifth of C4, but that one
    # old voice cannot explain three simultaneous new voices.
    refute voicer.send(:within_lead?, [55, 58, 62], [60, 80, 90])
    assert voicer.send(:within_lead?, [55, 78, 88], [60, 80, 90])
  end

  def test_recovered_transcriptions_carry_provenance
    rec = Dilla.recovered
    assert rec.dig("provenance", "transcription_sources").is_a?(Array)
    refute_empty rec.fetch("progressions")
    get_dis_money = rec.fetch("progressions").find { |p| p["id"] == "get_dis_money" }
    assert_equal 7, get_dis_money.fetch("loop_bars"), "Get Dis Money is the documented seven-bar loop"
    assert_equal "E", get_dis_money.fetch("pedal")
  end
end

class TestDillaHistoricalMaterial < Minitest::Test
  def sequencer(progress, seed: 7)
    groove = Dilla::Groove.new(
      bpm: progress["bpm"] || 86, swing: (progress.dig("feel", "swing") || 54),
      profile: Dilla.catalogue.fetch("groove_profiles").fetch("dilla_shadow"),
      performer: Dilla.catalogue.fetch("performers").first
    )
    Dilla::Sequencer.new(
      progress: progress, groove: groove, drums: {}, rig: {},
      rng: Dilla::Rng.new(seed), performer: Dilla.catalogue.fetch("performers").first
    )
  end

  def test_historical_artist_corpus_is_a_separate_first_class_source
    rows = Dilla.progressions.select { |row| row["source"] == "artist_verified" }
    assert_equal 16, rows.length
    assert_equal rows.length, rows.map { |row| row["id"] }.uniq.length
    %w[time_donut fall_in_love get_dis_money climax_slum_village so_what_miles
       brown_sugar_dangelo spanish_joint_dangelo the_root_dangelo].each do |id|
      assert rows.any? { |row| row["id"] == id }, "missing historical recording #{id}"
    end
    rows.each do |row|
      refute_empty row.fetch("sources"), "#{row['id']} needs source notes"
      assert_equal "restored_legacy_unverified", row.fetch("source_status")
    end
    charts = Dilla.progressions.select { |row| row["source"] == "chart_reference" }
    assert_equal 1, charts.length
    assert_equal "never_catch_me_flylo", charts.first.fetch("id")
    studies = Dilla.progressions.select { |row| row["source"] == "engine_study" }
    assert_equal 2, studies.length
    assert studies.all? { |row| row.fetch("note").include?("not a transcription") }
  end

  def test_archived_corpus_chord_timing_is_explicit_and_loop_complete
    rows = Dilla.progressions.select { |row| row["source"] == "artist_verified" }

    rows.each do |row|
      durations = row.fetch("chord_bars")
      assert_equal row.fetch("chords").length, durations.length, "#{row['id']} chord duration count"
      assert durations.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? },
             "#{row['id']} has invalid chord durations"
      assert_in_delta row.fetch("loop_bars"), durations.sum, 0.0001, "#{row['id']} loop duration"
      assert_includes %w[published_form source_loop_length_only engine_grid_assumption],
                      row.fetch("chord_timing_status")
      refute_empty row.fetch("chord_timing_note")
      refute_empty row.fetch("melody_status")
    end
  end

  def test_get_dis_money_separates_documented_loop_length_from_approximate_chord_positions
    progress = Dilla.progression_by_ref("get_dis_money")

    assert_equal 7, progress.fetch("loop_bars")
    assert_equal "source_loop_length_only", progress.fetch("chord_timing_status")
    progress.fetch("chord_bars").each do |duration|
      assert_in_delta 7.0 / 6.0, duration, 0.0001
    end
    assert_match(/engine approximation only/, progress.fetch("chord_timing_note"))
  end

  def test_time_keeps_render_tempo_separate_from_conflicting_community_reference
    progress = Dilla.progression_by_ref("time_donut")
    evidence = progress.fetch("tempo_evidence")

    assert_equal 86, progress.fetch("bpm")
    assert_equal "conflicting_secondary_reference", evidence.fetch("status")
    assert_equal 86, evidence.fetch("render_bpm")
    assert_equal 95, evidence.fetch("reported_bpm")
    assert_match(/pending direct audio measurement/, evidence.fetch("note"))
  end

  def test_source_record_tempo_and_form_override_the_generic_profile
    brown_sugar = Dilla::Options.new
    brown_sugar.progression = "brown_sugar_dangelo"
    assert_equal 83.0, Dilla.resolve_render_plan(brown_sugar).fetch(:bpm)

    so_what = Dilla::Options.new
    so_what.progression = "so_what_miles"
    plan = Dilla.resolve_render_plan(so_what)
    assert_equal 32, plan.fetch(:bars)
  end

  def test_so_what_retains_its_aaba_harmonic_durations
    progress = Dilla.progression_by_ref("so_what_miles")
    seq = sequencer(progress)
    plan = seq.send(:build_chord_plan, 8, 32)
    assert_equal %w[Dm7 Ebm7 Dm7], plan.map { |slot| progress.fetch("chords").fetch(slot[:index]) }
    assert_equal [16.0, 8.0, 8.0], plan.map { |slot| slot[:bars] }
  end

  def test_record_specific_voicings_survive_the_generic_voicer
    chord = Dilla::ChordParser.parse("Ebm7fil", Dilla.theory)
    assert_equal [51, 54, 58, 61, 65], chord[:voicing_midi]
    voiced = Dilla::Voicer.new(Dilla.theory).voice([chord], Dilla::Rng.new(1)).first
    assert_equal [63, 66, 70, 73, 77], voiced
  end

  def test_minor_eleventh_can_use_the_five_note_quartal_stack
    chord = Dilla::ChordParser.parse("Cm11", Dilla.theory)
    voiced = Dilla::Voicer.new(Dilla.theory).voice([chord], Dilla::Rng.new(1)).first
    assert_equal [55, 60, 65, 70, 75], voiced
  end

  def test_bass_lane_honours_slash_bass_inversions
    progress = {
      "id" => "slash_bass_dub",
      "chords" => ["Bb/E"],
      "feel" => { "bass" => "dub" }
    }
    seq = sequencer(progress)
    chord = Dilla::ChordParser.parse("Bb/E", Dilla.theory)
    slot = { index: 0, start_bar: 0, bars: 1 }

    events = seq.send(:bass_events, chord, slot, [chord], [slot])
    assert_equal [40, 40, 40], events.first(3).map(&:midi)
  end

  def test_walking_bass_approaches_the_next_slash_bass_note
    progress = {
      "id" => "slash_bass_walk",
      "chords" => ["Bb/E", "C/F#"],
      "feel" => { "bass" => "walk" }
    }
    seq = sequencer(progress)
    parsed = progress.fetch("chords").map { |symbol| Dilla::ChordParser.parse(symbol, Dilla.theory) }
    slot = { index: 0, start_bar: 0, bars: 1 }

    events = seq.send(:bass_events, parsed.first, slot, parsed, [slot])
    assert_equal 41, events.last.midi, "F2 leads by a semitone into the next F#2 slash bass"
  end

  def test_time_keeps_the_historical_measured_chop_contour
    progress = Dilla.progression_by_ref("time_donut")
    seq = sequencer(progress)
    chord = Dilla::ChordParser.parse(progress.fetch("chords").first, Dilla.theory)
    events = seq.send(:melody_events, chord, { start_bar: 0, bars: 1 }, nil)
    assert_equal [76, 74, 72, 69, 67], events.map(&:midi)
  end

  def test_held_chords_carry_the_melody_through_their_full_duration
    progress = Dilla.progression_by_ref("so_what_miles").merge("melody_midi" => [76, 74, 72, 69, 67, 65])
    seq = sequencer(progress)
    chord = Dilla::ChordParser.parse("Dm7", Dilla.theory)
    events = seq.send(:melody_events, chord, { start_bar: 0, bars: 16 }, nil)
    assert_equal 80, events.length, "five-note rhythm should repeat across sixteen held bars"
    assert_operator events.last.time, :>, seq.instance_variable_get(:@groove).bar_s * 15.0
  end

  def test_generated_melody_stays_in_the_chord_or_scale
    progress = Dilla.progressions.find { |row| row["source"] == "artist_verified" && !row["melody_midi"] }
    seq = sequencer(progress)
    chord = Dilla::ChordParser.parse("Bbmaj7", Dilla.theory)
    scale = Dilla.scale_for(chord, Dilla.theory)
    allowed = (chord[:intervals].map { |iv| (chord[:root] + iv) % 12 } +
               scale.map { |degree| (chord[:root] + degree) % 12 }).uniq

    40.times do
      note = seq.send(:pick_melody_note, chord, scale, chord[:root], false, "sweet_soul")
      assert note.between?(72, 83)
      assert_includes allowed, note % 12
    end
  end

  def test_float_melody_steps_are_not_mistaken_for_integer_sixteenths
    groove = Dilla::Groove.new(bpm: 86, swing: 58, profile: {}, performer: {})
    seq = sequencer({})
    straight = groove.sixteenth_s
    assert_in_delta 1.5 * straight, seq.send(:step_time, 0, 1.5, "melody"), 1e-12
    assert_in_delta straight + groove.swing_delay_s("melody"),
                    seq.send(:step_time, 0, 1, "melody"), 1e-12
  end

  def test_soul_clap_leads_the_snare
    profile = Dilla.catalogue.fetch("groove_profiles").fetch("dilla_shadow")
    groove = Dilla::Groove.new(
      bpm: 86, swing: 54, profile: profile,
      performer: Dilla.catalogue.fetch("performers").first
    )
    assert_equal(-18.0, groove.clap_early_ms)
    assert_operator groove.clap_early_ms, :<, groove.nudge("snare")
  end
end

class TestDillaRender < Minitest::Test
  def ruby
    RbConfig.ruby
  end

  def dilla
    File.expand_path("../dilla/dilla.rb", __dir__)
  end

  def read_wav_header(path)
    header = File.binread(path, 44)
    riff, _size, wave = header.unpack("A4VA4")
    _fmt_id, _fmt_size, _audio_fmt, channels, sample_rate, _byte_rate, _align, bits = header[12, 24].unpack("A4VvvVVvv")
    [riff, wave, channels, sample_rate, bits]
  end

  def test_deterministic_seed_produces_identical_renders
    Dir.mktmpdir do |dir|
      outs = [1, 2].map do |i|
        path = File.join(dir, "take#{i}.wav")
        out, err, status = Open3.capture3(RbConfig.ruby, dilla, "--progression", "1", "--bars", "1",
                                          "--seed", "4242", "--out", path, chdir: File.dirname(dilla))
        assert status.success?, err
        path
      end
      digest = ->(p) { Digest::SHA256.file(p).hexdigest }
      assert_equal digest.call(outs[0]), digest.call(outs[1]), "same seed must reproduce the same take"
    end
  end

  def test_render_writes_quality_session_and_provenance_sidecars
    Dir.mktmpdir do |dir|
      base = File.join(dir, "take")
      _out, err, status = Open3.capture3(RbConfig.ruby, dilla, "--progression", "1", "--bars", "1",
                                         "--seed", "7", "--out", base, chdir: File.dirname(dilla))
      assert status.success?, err
      %w[.quality.json .session.json .provenance.json].each do |suffix|
        assert File.file?("#{base}#{suffix}"), "missing sidecar #{suffix}"
      end
      quality = JSON.parse(File.read("#{base}.quality.json"))
      assert_operator quality.fetch("lufs_estimate"), :<, -7.0, "boom-bap masters must not sit at streaming loudness"
      assert_operator quality.fetch("lufs_estimate"), :>, -16.0
      assert_operator quality.fetch("peak_dbfs"), :<, 0.0
      shares = quality.fetch("stem_energy_share")
      assert_operator shares.fetch("drums"), :>=, 0.12, "drums must carry the mix"
      provenance = JSON.parse(File.read("#{base}.provenance.json"))
      render = provenance.fetch("render")
      assert_equal File.size("#{base}.wav"), render.fetch("bytes")
      assert_equal Digest::SHA256.file("#{base}.wav").hexdigest, render.fetch("sha256")
      riff, wave, channels, sample_rate, bits = read_wav_header("#{base}.wav")
      assert_equal "RIFF", riff
      assert_equal "WAVE", wave
      assert_equal 2, channels
      assert_equal 44_100, sample_rate
      assert_equal 16, bits
    end
  end

  def test_atomic_write_keeps_the_previous_artifact_when_replacement_fails
    Dir.mktmpdir do |dir|
      path = File.join(dir, "take.json")
      File.write(path, "previous")
      original_mode = File.stat(path).mode & 0o777

      File.stub(:rename, ->(*) { raise IOError, "simulated rename failure" }) do
        assert_raises(IOError) { Dilla.atomic_write(path, "replacement") }
      end

      assert_equal "previous", File.read(path)
      assert_equal original_mode, File.stat(path).mode & 0o777
      refute Dir.children(dir).any? { |name| name.start_with?(".take.json.") }
    end
  end

  def test_drum_balance_flag_moves_the_mix
    Dir.mktmpdir do |dir|
      readings = {}
      [-6, 6].each do |db|
        base = File.join(dir, "bal#{db}")
        _out, err, status = Open3.capture3(RbConfig.ruby, dilla, "--progression", "1", "--bars", "1",
                                           "--seed", "9", "--drum-balance", db.to_s, "--out", base,
                                           chdir: File.dirname(dilla))
        assert status.success?, err
        readings[db] = JSON.parse(File.read("#{base}.quality.json")).fetch("stem_energy_share").fetch("drums")
      end
      assert_operator readings[6], :>, readings[-6], "+6dB drums must outweigh -6dB drums"
    end
  end

  def test_sample_flip_chops_a_rights_cleared_loop
    Dir.mktmpdir do |dir|
      loop_path = File.join(dir, "crate.wav")
      # A rights-cleared operator-style loop: a simple sine groove rendered inline.
      ruby_snake = <<~'RB'
        sr = 44100
        n = sr * 4
        data = Array.new(n) do |i|
          t = i.to_f / sr
          f = [220.0, 261.63, 293.66, 329.63][(t / 0.5).to_i % 4]
          (Math.sin(2 * Math::PI * f * t) * 0.4 + Math.sin(2 * Math::PI * 55 * t) * 0.3)
        end
        pcm = data.map { |v| (v * 32767).round }.pack("s<#{n}")
        hdr = ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, sr, sr * 2, 2, 16, "data", pcm.bytesize].pack("A4VA4A4VvvVVvvA4V")
        File.binwrite(ARGV[0], hdr + pcm)
      RB
      _o, err, status = Open3.capture3(RbConfig.ruby, "-e", ruby_snake, loop_path)
      assert status.success?, err

      base = File.join(dir, "chopped")
      out, err, status = Open3.capture3(
        { "SAMPLE_LOOP" => loop_path, "SAMPLE_LOOP_VOL" => "0.42", "SAMPLE_LOOP_WEIGHT" => "0.6" },
        RbConfig.ruby, dilla, "--progression", "1", "--bars", "2", "--seed", "5",
        "--out", base, chdir: File.dirname(dilla)
      )
      assert status.success?, err
      session = JSON.parse(File.read("#{base}.session.json"))
      flip = session.fetch("sample_flip")
      assert_equal loop_path, flip.fetch("source")
      assert_equal 8, flip.fetch("slices")
      assert flip.fetch("picked").length.positive?
      quality = JSON.parse(File.read("#{base}.quality.json"))
      assert_operator quality.fetch("stem_energy_share").fetch("sample"), :>, 0.0
    end
  end
end

class TestDillaReferenceProfile < Minitest::Test
  def test_profile_schema_matches_what_master_reads
    features = {
      "bpm" => 87.59, "bpm_confidence" => 0.98, "duration_s" => 30.0,
      "onset_density_per_bar" => 8.2, "offbeat_onset_share" => 0.349,
      "timing_spread_ms" => 40.54, "swing_ratio" => 0.63,
      "drums_energy_share" => 0.179, "bass_energy_share" => 0.197,
      "other_energy_share" => 0.624, "vocal_energy_share" => 0.0,
      "brightness_hz" => 1606.1,
      "harmony" => { "key" => "F maj", "chord_changes" => 6, "chords" => [] },
      "melody" => { "median_hz" => 236.9 }, "drum_grid" => { "kick" => [1.0] * 16 }, "sections" => []
    }
    profile = Dilla.build_profile(features, { "title" => "x" }, "j_dilla", "/tmp/x.wav", nil)
    assert_equal "j_dilla", profile.fetch("style_key")
    assert_in_delta 87.6, profile.fetch("target_bpm"), 0.01
    assert_equal "dilla_shadow", profile.fetch("groove_profile")
    feats = profile.fetch("features")
    %w[onset_density_per_bar offbeat_onset_share timing_spread_ms drums_energy_share other_energy_share].each do |key|
      assert feats.key?(key), "media_intent reads features[#{key}]"
    end
  end

  def test_swung_and_loose_recordings_map_to_the_dilla_pocket
    features = { "bpm" => 92.0, "swing_ratio" => 0.61, "timing_spread_ms" => 14.0,
                 "onset_density_per_bar" => 9.0, "offbeat_onset_share" => 0.5,
                 "drums_energy_share" => 0.3, "other_energy_share" => 0.4 }
    profile = Dilla.build_profile(features, {}, "j_dilla", "/tmp/x.wav", nil)
    assert_equal "dilla_shadow", profile.fetch("groove_profile")
  end

  def test_analyzer_reports_tempo_and_valid_json_without_nan
    Dir.mktmpdir do |dir|
      # Two bars at 86 BPM: kick on 1 and 3, snare on 2 and 4, hats on 8ths.
      bar = 60.0 / 86 * 4
      sr = 44_100
      n = (bar * 2 * sr).to_i
      audio = Array.new(n, 0.0)
      rng = Random.new(7)
      kick_at = [0.0, bar / 2, bar, bar * 1.5]
      snare_at = [bar / 4, bar * 3 / 4, bar * 5 / 4, bar * 7 / 4]
      kick_at.each do |time|
        start = (time * sr).to_i
        (0.3 * sr).to_i.times do |index|
          sample = start + index
          next if sample >= n

          audio[sample] += Math.sin(2 * Math::PI * 48 * index / sr * 4) *
                           Math.exp(-index.to_f / (0.06 * sr)) * 0.9
        end
      end
      snare_at.each do |time|
        start = (time * sr).to_i
        (0.15 * sr).to_i.times do |index|
          sample = start + index
          next if sample >= n

          audio[sample] += (rng.rand * 2 - 1) * Math.exp(-index.to_f / (0.04 * sr)) * 0.7
        end
      end
      (n / 2).times do |index|
        time = index * 2.0 / sr
        next unless (time % (bar / 8)).zero?

        audio[index * 2] += (rng.rand * 2 - 1) * 0.35
      end
      pcm = audio.map { |value| (value.clamp(-1, 1) * 32_767).round }.pack("s<#{n}")
      header = ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, sr, sr * 2, 2, 16,
                "data", pcm.bytesize].pack("A4VA4A4VvvVVvvA4V")
      wav = File.join(dir, "two_bar.wav")
      File.binwrite(wav, header + pcm)
      features_path = File.join(dir, "features.json")
      features = Studio::DillaReference::Analyzer.new.write(wav, features_path)
      text = File.read(features_path)
      refute_match(/NaN|Infinity/, text, "the analyzer must not emit non-standard numeric tokens")
      archived = JSON.parse(text)
      assert_equal features, archived
      assert_in_delta 86.0, features.fetch("bpm"), 3.0, "a two-bar 86 BPM fixture must be measured near 86"
      %w[onset_density_per_bar offbeat_onset_share timing_spread_ms swing_ratio brightness_hz].each do |key|
        assert features.key?(key), "missing measured feature #{key}"
      end
      assert_equal %w[hat kick snare], features.fetch("drum_grid").keys.sort
      assert features.fetch("bpm_confidence").between?(0.0, 1.0)
    end
  end

  def test_analyzer_applies_a_finite_ten_minute_default_limit
    analyzer = Studio::DillaReference::Analyzer.new
    assert_equal 600, analyzer.send(:normalize_duration, nil)
    assert_equal 12.5, analyzer.send(:normalize_duration, 12.5)
    assert_raises(Studio::DillaReference::AnalysisError) do
      analyzer.send(:normalize_duration, Studio::DillaReference::Analyzer::MAX_SECONDS + 1)
    end
    assert_raises(Studio::DillaReference::AnalysisError) do
      analyzer.send(:normalize_duration, Float::INFINITY)
    end
  end
end

class TestDillaIndustrialTechno < Minitest::Test
  def test_renders_a_four_on_the_floor_take
    Dir.mktmpdir do |dir|
      base = File.join(dir, "techno")
      _out, err, status = Open3.capture3(RbConfig.ruby, File.expand_path("../dilla/dilla.rb", __dir__),
                                         "industrial-techno", "--out", base, "--bars", "2", "--bpm", "130",
                                         chdir: File.expand_path("..", __dir__))
      assert status.success?, err
      assert File.file?("#{base}.wav")
      quality = JSON.parse(File.read("#{base}.quality.json"))
      assert_operator quality.fetch("peak_dbfs"), :<, 0.0
    end
  end
end

class TestDillaArrangementAndOfflineExport < Minitest::Test
  def test_showcase_is_a_real_24_bar_multi_progression_arrangement
    show = Dilla.showcase_data
    plan = Dilla.resolve_render_plan(Dilla::Options.new, showcase: show)
    assert_equal 24, plan.fetch(:bars)
    sections = plan.fetch(:arrangement)
    assert_equal %w[intro head lift outro], sections.map { |section| section.fetch("section") }
    assert_equal %w[blue_hour blue_hour coltrane_soup rain_on_glass], sections.map { |section| section.fetch("progression") }
    assert_equal 8, sections.fetch(2).fetch("bars")
    assert_includes sections.fetch(2).fetch("layers"), "foley"
  end

  def test_offline_style_profiles_resolve_without_network_services
    profiles = Dilla.catalogue.fetch("production_profiles")
    %w[j_dilla flying_lotus jazz_soul funk ambient drum_and_bass noise_sound_design royksopp].each do |name|
      assert profiles.key?(name), "missing local production profile #{name}"
    end
    plan = Dilla.resolve_render_plan(Dilla::Options.new.tap { |opts| opts.style = "flying_lotus" })
    assert_equal "coltrane_soup", plan.fetch(:progression).fetch("id")
    assert_equal "flylo_knock", plan.fetch(:drums)
    assert_equal "prophet_5", plan.fetch(:voice)
  end

  def test_midi_writer_emits_a_standard_multitrack_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "score.mid")
      events = {
        chord: [Dilla::Event.new(0.0, 0.75, :chord, [60, 64, 67], 0.8, nil)],
        drum: [Dilla::Event.new(0.5, 0.0, :kick, nil, 1.0, nil)]
      }
      Dilla::MidiWriter.write(path, events, bpm: 90)
      bytes = File.binread(path)
      assert_equal "MThd", bytes[0, 4]
      assert_equal 1, bytes[8, 2].unpack1("n")
      assert_equal 6, bytes[10, 2].unpack1("n")
      assert_equal 960, bytes[12, 2].unpack1("n")
      assert_operator bytes.bytesize, :>, 100
    end
  end

  def test_midi_flags_are_parsed_without_optional_gems
    opts = Dilla.parse_cli(["--midi", "--foley", "--midi-out", "score.mid"])
    assert opts.midi
    assert opts.foley
    assert_equal "score.mid", opts.midi_out
  end
end

class TestDillaStyleProfileRouting < Minitest::Test
  def test_style_profile_selects_its_own_progression_voice_and_groove
    opts = Dilla::Options.new
    opts.style = "flying_lotus"
    plan = Dilla.resolve_render_plan(opts)
    assert_equal "coltrane_soup", plan.fetch(:progression).fetch("id")
    assert_equal "flylo_knock", plan.fetch(:drums)
    assert_equal "prophet_5", plan.fetch(:voice)
    assert_equal "los_angeles", plan.fetch(:profile)
  end

  def test_showcase_plan_passes_all_four_sections_to_the_sequencer
    plan = Dilla.resolve_render_plan(Dilla::Options.new, showcase: Dilla.showcase_data)
    assert_equal 24, plan.fetch(:bars)
    assert_equal 4, plan.fetch(:arrangement).length
    assert_equal "coltrane_soup", plan.fetch(:arrangement)[2].fetch("progression")
  end
end

class TestDillaInstrumentVelocity < Minitest::Test
  def rms(samples)
    Math.sqrt(samples.sum { |sample| sample * sample } / [samples.length, 1].max)
  end

  def test_velocity_changes_amplitude_across_the_instrument_bank
    kit = Dilla.catalogue.fetch("kits").fetch("kit_dust")
    voices = %w[
      rhodes_mark1 glass_pad music_box church_organ prophet_5 juno_106
      minimoog_solo wurlitzer_200a
    ]
    voices.each do |name|
      engine = Dilla::Instruments.new(kit, Dilla.catalogue.fetch("voices").fetch(name), Dilla.theory)
      quiet = engine.chord_note(60, 0.22, 0.12)
      loud = engine.chord_note(60, 0.78, 0.12)
      assert_operator rms(loud), :>, rms(quiet), "#{name} must respect MIDI velocity"
    end
  end

  def test_bass_velocity_changes_amplitude
    kit = Dilla.catalogue.fetch("kits").fetch("kit_dust")
    engine = Dilla::Instruments.new(kit, Dilla.catalogue.fetch("voices").fetch("tape_strings"), Dilla.theory)
    quiet = engine.bass(36, 0.2, 0.18)
    loud = engine.bass(36, 0.8, 0.18)
    assert_operator rms(loud), :>, rms(quiet)
  end
end

class TestDillaFMDrumVoices < Minitest::Test
  def rms(samples)
    Math.sqrt(samples.sum { |sample| sample * sample } / [samples.length, 1].max)
  end

  def test_fm_kick_snare_hat_and_clap_render_distinct_velocity_sensitive_audio
    kit = Dilla.catalogue.fetch("kits").fetch("kit_dust")
    drums = Dilla::DrumKit.new(kit)
    {
      kick: [drums.kick(0.22), drums.kick(0.78)],
      snare: [drums.snare(0.22), drums.snare(0.78)],
      hat: [drums.hat(0.22), drums.hat(0.78)],
      soulclap: [drums.soulclap(0.22), drums.soulclap(0.78)]
    }.each do |name, (quiet, loud)|
      assert_operator quiet.length, :>, 0, "#{name} must render samples"
      assert_operator rms(loud), :>, rms(quiet), "#{name} must preserve velocity dynamics"
      assert quiet.all?(&:finite?), "#{name} must not emit non-finite samples"
    end
  end

  def test_drum_kits_have_distinct_fm_operator_profiles
    kits = Dilla.catalogue.fetch("kits")
    dust = kits.fetch("kit_dust")
    break_kit = kits.fetch("kit_break")
    basement = kits.fetch("kit_basement")
    refute_equal dust.dig("kick", "fm_ratio"), break_kit.dig("kick", "fm_ratio")
    refute_equal break_kit.dig("snare", "fm_index"), basement.dig("snare", "fm_index")
    refute_equal dust.dig("hat", "fm_ratio"), basement.dig("hat", "fm_ratio")
  end
end

class TestDillaRoyksoppProfile < Minitest::Test
  def test_royksopp_is_a_distinct_six_chord_synth_pop_lane
    opts = Dilla::Options.new
    opts.style = "royksopp"
    plan = Dilla.resolve_render_plan(opts)
    assert_equal "dusty_paradise", plan.fetch(:progression).fetch("id")
    assert_equal 6, plan.fetch(:progression).fetch("chords").length
    assert_equal "royksopp_pulse", plan.fetch(:drums)
    assert_equal "juno_106", plan.fetch(:voice)
    assert_equal "on_grid", plan.fetch(:profile)
  end
end


class TestRG69BrowserContract < Minitest::Test
  def studio_root
    File.expand_path("..", __dir__)
  end

  def test_rg69_assets_are_separate_and_resolve
    html_path = File.join(studio_root, "rg69.html")
    css_path = File.join(studio_root, "rg69.css")
    js_path = File.join(studio_root, "rg69.js")
    [html_path, css_path, js_path].each { |path| assert File.file?(path), "missing #{path}" }

    html = File.read(html_path)
    assert_match(/<html[^>]+lang=["']en["']/i, html)
    assert_match(/<meta\s+charset=["']?utf-8/i, html)
    assert_includes html, 'href="rg69.css"'
    assert_includes html, 'src="rg69.js"'
    assert_includes html, "tone/14.8.49/Tone.min.js"
    assert_includes html, 'href="#main-content"'
    assert_includes html, 'id="main-content"'
    refute_match(/<style\b|<script(?![^>]*\bsrc=)/i, html)
    refute_match(/\sstyle=["']/i, html)

    javascript = File.read(js_path)
    refute_match(/\.innerHTML\b|\beval\s*\(/, javascript)
    assert_includes javascript, "document.createTextNode"
    assert_includes File.read(css_path), "prefers-reduced-motion"
    assert_includes File.read(css_path), ":focus-visible"
  end
end

class TestDillaSeedReproducibility < Minitest::Test
  def test_generated_seed_replays_the_exact_random_stream
    initial = Dilla::Rng.new(nil)
    recorded_seed = initial.seed
    first_draws = Array.new(24) { initial.rand }

    replay = Dilla::Rng.new(recorded_seed)
    assert_equal first_draws, Array.new(24) { replay.rand }
  end

  def test_seeded_drum_textures_repeat_without_process_global_randomness
    kit = Dilla.catalogue.fetch("kits").fetch("kit_break")
    render_hits = lambda do |seed|
      drums = Dilla::DrumKit.new(kit, rng: Random.new(seed ^ 0xD11A))
      {
        snare: drums.snare(0.82),
        hat: drums.hat(0.55),
        ride: drums.ride(0.4),
        perc: drums.perc(0.35)
      }
    end

    first = render_hits.call(23)
    repeat = render_hits.call(23)
    another_take = render_hits.call(24)

    assert_equal first, repeat
    refute_equal first, another_take
  end
end
