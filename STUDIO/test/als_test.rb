# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "zlib"
require "stringio"
require_relative "minitest_helper"
require_relative "../dilla/lib/als"
require_relative "../dilla/lib/als_export"
require_relative "../dilla/lib/als_to_midi"

class TestAbletonLiveSetRecovery < Minitest::Test
  def live_set_xml
    <<~XML
      <Ableton MajorVersion="12" MinorVersion="0" Creator="Ableton Live">
        <LiveSet>
          <Tracks>
            <MidiTrack Id="10">
              <Name><EffectiveName Value="MIDI"/><UserName Value="Drums"/></Name>
              <DeviceChain><MainSequencer><ClipSlotList>
                <ClipSlot><ClipSlot>
                  <MidiClip Id="101" Time="4.0" Duration="8.0">
                    <Name><UserName Value="Drum phrase"/></Name>
                    <CurrentStart Value="0.0"/><CurrentEnd Value="8.0"/>
                    <Loop><LoopStart Value="1.0"/><LoopEnd Value="5.0"/><LoopOn Value="true"/></Loop>
                    <Notes><KeyTracks>
                      <KeyTrack><MidiKey Value="36"/><Notes>
                        <MidiNoteEvent NoteId="1" Time="0.5" Duration="0.25" Velocity="127" OffVelocity="64" IsEnabled="true"/>
                        <MidiNoteEvent NoteId="2" Time="1.5" Duration="0.5" Velocity="89" IsEnabled="false"/>
                        <MidiNoteEvent NoteId="3" Time="2.5" Duration="0.5" Velocity="100" IsEnabled="true"/>
                      </Notes></KeyTrack>
                    </KeyTracks></Notes>
                  </MidiClip>
                </ClipSlot></ClipSlot>
              </ClipSlotList></MainSequencer></DeviceChain>
              <AutomationEnvelope><AutomationTarget Id="44"/><Events><FloatEvent Time="0.0" Value="0.8"/><FloatEvent Time="4.0" Value="0.4"/></Events></AutomationEnvelope>
            </MidiTrack>
            <MidiTrack Id="11">
              <Name><UserName Value="Rhodes"/><EffectiveName Value="Electric Piano"/></Name>
              <DeviceChain><MainSequencer><ClipSlotList>
                <ClipSlot><ClipSlot>
                  <MidiClip Id="102" Time="0.0" Duration="4.0">
                    <Name><UserName Value="Chords"/></Name>
                    <Loop><LoopStart Value="0.0"/><LoopEnd Value="4.0"/><LoopOn Value="false"/></Loop>
                    <Notes><KeyTracks>
                      <KeyTrack><MidiKey Value="60"/><Notes>
                        <MidiNoteEvent Time="0.0" Duration="1.0" Velocity="104" OffVelocity="64" IsEnabled="true"/>
                      </Notes></KeyTrack>
                      <KeyTrack><MidiKey Value="64"/><Notes>
                        <MidiNoteEvent Time="0.0" Duration="1.0" Velocity="96" IsEnabled="true"/>
                      </Notes></KeyTrack>
                    </KeyTracks></Notes>
                  </MidiClip>
                </ClipSlot></ClipSlot>
              </ClipSlotList></MainSequencer></DeviceChain>
            </MidiTrack>
            <AudioTrack Id="12">
              <Name><UserName Value="Sample chops"/></Name>
              <DeviceChain><MainSequencer><ClipSlotList>
                <ClipSlot><ClipSlot>
                  <AudioClip Id="103" Time="8.0" Duration="4.0">
                    <Name><UserName Value="Soul sample"/></Name>
                    <Sample><FileRef><Name Value="break.wav"/><Path Value="/Archive/Samples/Imported/break.wav"/><RelativePath Value="Samples/Imported/break.wav"/><Type Value="2"/></FileRef></Sample>
                    <IsWarped Value="true"/><WarpMarkers><WarpMarker SecTime="0.0" BeatTime="0.0"/><WarpMarker SecTime="2.0" BeatTime="4.0"/></WarpMarkers>
                  </AudioClip>
                </ClipSlot></ClipSlot>
              </ClipSlotList></MainSequencer></DeviceChain>
            </AudioTrack>
          </Tracks>
          <MasterTrack><DeviceChain><Mixer>
            <Tempo><Manual Value="93.5"/></Tempo>
            <TimeSignature><Numerator Value="4"/><Denominator Value="4"/></TimeSignature>
          </Mixer></DeviceChain></MasterTrack>
        </LiveSet>
      </Ableton>
    XML
  end

  def write_set(directory, compressed: true)
    path = File.join(directory, compressed ? "session.als" : "session.xml")
    bytes = if compressed
              io = StringIO.new("".b)
              writer = Zlib::GzipWriter.new(io)
              writer.write(live_set_xml)
              writer.close
              io.string
            else
              live_set_xml
            end
    File.binwrite(path, bytes)
    path
  end

  def test_parses_gzipped_als_tempo_tracks_clips_and_notes_in_beats
    Dir.mktmpdir do |directory|
      project = Studio::ALS::Parser.new.parse(write_set(directory))
      assert_equal "session", project.fetch("title")
      assert_equal 93.5, project.fetch("tempo_bpm")
      assert_equal({ "numerator" => 4, "denominator" => 4 }, project.fetch("time_signature"))
      assert_equal %w[Drums Rhodes Sample chops], project.fetch("tracks").map { |track| track.fetch("name") }
      drum_clip = project.fetch("tracks").first.fetch("clips").first
      assert_equal 4.0, drum_clip.fetch("start_beats")
      assert_equal 8.0, drum_clip.fetch("length_beats")
      assert_equal true, drum_clip.fetch("loop_enabled")
      assert_equal [36, 36, 36], drum_clip.fetch("notes").map { |note| note.fetch("pitch") }
      assert_equal [127.0, 89.0, 100.0], drum_clip.fetch("notes").map { |note| note.fetch("velocity_raw") }
      assert_in_delta 89.0 / 127.0, drum_clip.fetch("notes").last.fetch("velocity"), 1e-9
      assert_equal false, drum_clip.fetch("notes")[1].fetch("enabled")
      assert_in_delta 89.0 / 127.0, drum_clip.fetch("notes")[1].fetch("velocity"), 1e-9
      assert_equal 64.0, drum_clip.fetch("notes").first.fetch("release_velocity")
      assert_equal 0.5, drum_clip.fetch("notes").first.fetch("start_beats")
    end
  end

  def test_accepts_extracted_plain_xml_for_diagnostics
    Dir.mktmpdir do |directory|
      project = Studio::ALS::Parser.new.parse(write_set(directory, compressed: false))
      assert_equal 3, project.fetch("tracks").length
      assert_equal "audio", project.fetch("tracks").last.fetch("kind")
      reference = project.fetch("tracks").last.fetch("clips").first.fetch("audio_references").first
      assert_equal "/Archive/Samples/Imported/break.wav", reference.fetch("path")
      assert_equal "Samples/Imported/break.wav", reference.fetch("relative_path")
      audio_clip = project.fetch("tracks").last.fetch("clips").first
      assert_equal true, audio_clip.fetch("is_warped")
      assert_equal [{ "seconds" => 0.0, "beats" => 0.0 }, { "seconds" => 2.0, "beats" => 4.0 }], audio_clip.fetch("warp_markers")
    end
  end

  def test_parser_extracts_automation_points_without_claiming_device_state
    Dir.mktmpdir do |directory|
      project = Studio::ALS::Parser.new.parse(write_set(directory))
      automation = project.fetch("tracks").first.fetch("automation").first
      assert_equal "44", automation.fetch("target_id")
      assert_equal [0.8, 0.4], automation.fetch("points").map { |point| point.fetch("value") }
      assert_match(/device parameters/, project.fetch("limitations").fetch("device_state"))
    end
  end

  def test_rejects_malformed_and_entity_declared_xml
    parser = Studio::ALS::Parser.new
    assert_raises(Studio::ALS::ParseError) { parser.parse(StringIO.new("<Ableton><LiveSet>")) }
    unsafe = '<!DOCTYPE x [<!ENTITY a "boom">]><Ableton><LiveSet/></Ableton>'
    assert_raises(Studio::ALS::ParseError) { parser.parse(StringIO.new(unsafe)) }
  end

  def test_dual_export_preserves_composition_and_generates_standalone_ruby
    Dir.mktmpdir do |directory|
      project = Studio::ALS::Parser.new.parse(write_set(directory))
      json_path = File.join(directory, "session.json")
      ruby_path = File.join(directory, "session.rb")
      Studio::ALS::Export.write_both(project, json_path:, ruby_path:)
      archived = JSON.parse(File.read(json_path))
      assert_equal project.fetch("tracks").length, archived.fetch("tracks").length
      ruby_source = File.read(ruby_path)
      assert_includes ruby_source, "track("
      assert_includes ruby_source, "clip("
      assert_includes ruby_source, "note("
      _out, error, status = Open3.capture3(RbConfig.ruby, "-c", ruby_path)
      assert status.success?, error
    end
  end

  def test_midi_export_writes_multitrack_file_and_routes_drum_track_to_channel_ten
    Dir.mktmpdir do |directory|
      project = Studio::ALS::Parser.new.parse(write_set(directory))
      path = Studio::ALS::MidiExporter.new.write(project, File.join(directory, "session.mid"))
      bytes = File.binread(path)
      assert_equal "MThd", bytes[0, 4]
      assert_equal 1, bytes[8, 2].unpack1("n")
      assert_equal 3, bytes[10, 2].unpack1("n") # tempo + two MIDI tracks
      assert_equal 960, bytes[12, 2].unpack1("n")
      assert_equal 1, bytes.scan([0x99, 36, 127].pack("C*")).length # pickup before loop start plays once
      assert_equal 2, bytes.scan([0x99, 36, 100].pack("C*")).length # note inside loop is repeated
      assert_includes bytes, [0x81, 60, 104].pack("C*") # Rhodes on channel 2, original Ableton velocity preserved
      assert_includes bytes, [0x81, 60, 64].pack("C*")
      refute_includes bytes, [0x99, 36, 89].pack("C*") # disabled note is excluded
    end
  end
end


class TestAbletonArchiveInventory < Minitest::Test
  def test_directory_scan_indexes_good_sets_and_keeps_going_after_bad_files
    Dir.mktmpdir do |directory|
      nested = File.join(directory, "Band", "Album")
      Dir.mkdir(File.join(directory, "Band"))
      Dir.mkdir(nested)
      source = File.join(directory, "one.als")
      writer = Zlib::GzipWriter.new(File.open(source, "wb"))
      writer.write(TestAbletonLiveSetRecovery.allocate.live_set_xml)
      writer.close
      File.binwrite(File.join(nested, "two.als"), File.binread(source))
      File.write(File.join(directory, "broken.als"), "not xml")

      inventory = Studio::ALS::Inventory.new.scan(directory, export_all: true)
      assert_equal 2, inventory.fetch("set_count")
      assert File.file?(File.join(directory, "one.json"))
      assert File.file?(File.join(directory, "one.rb"))
      assert File.file?(File.join(nested, "two.json"))
      assert File.file?(File.join(nested, "two.rb"))
      assert_equal 1, inventory.fetch("failure_count")
      assert_equal ["Band/Album/two.als", "one.als"], inventory.fetch("sets").map { |set| set.fetch("path") }.sort
      assert_equal 2, inventory.fetch("sets").first.fetch("midi_track_count")
      assert_match(/broken\.als/, inventory.fetch("failures").first.fetch("path"))
    end
  end
end


class TestAbletonAudioBridge < Minitest::Test
  def executable(path, body)
    File.write(path, "#!/usr/bin/env ruby\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def test_optional_fluidsynth_and_analog_stages_are_local_and_non_destructive
    Dir.mktmpdir do |directory|
      midi = File.join(directory, "set.mid")
      soundfont = File.join(directory, "bank.sf2")
      File.binwrite(midi, "MThd")
      File.binwrite(soundfont, "SF2")
      fluidsynth = executable(
        File.join(directory, "fluidsynth"),
        'args = ARGV; File.binwrite(args.fetch(args.index("-F") + 1), "neutral wav")'
      )
      ffmpeg = executable(
        File.join(directory, "ffmpeg"),
        'File.binwrite(ARGV.last, "processed wav")'
      )
      neutral = File.join(directory, "recovered.wav")
      processed = File.join(directory, "recovered-analog.wav")
      result = Studio::ALS::AudioRenderer.new(fluidsynth:, ffmpeg:).render(
        midi_path: midi, soundfont:, wav_path: neutral, analog: true, analog_path: processed
      )
      assert_equal neutral, result.fetch(:wav)
      assert_equal processed, result.fetch(:analog_wav)
      assert_equal "neutral wav", File.binread(neutral)
      assert_equal "processed wav", File.binread(processed)
    end
  end

  def test_timeout_keeps_previous_neutral_render_and_cleans_temporary_file
    Dir.mktmpdir do |directory|
      midi = File.join(directory, "set.mid")
      soundfont = File.join(directory, "bank.sf2")
      File.binwrite(midi, "MThd")
      File.binwrite(soundfont, "SF2")
      slow = executable(File.join(directory, "slow-fluidsynth"), "sleep 5")
      destination = File.join(directory, "kept.wav")
      File.binwrite(destination, "previous neutral render")

      error = assert_raises(Studio::ALS::AudioRenderError) do
        Studio::ALS::AudioRenderer.new(fluidsynth: slow, timeout: 0.05).render(
          midi_path: midi, soundfont:, wav_path: destination
        )
      end
      assert_match(/timed out/, error.message)
      assert_equal "previous neutral render", File.binread(destination)
      refute Dir.children(directory).any? { |name| name.end_with?(".tmp.wav") }
    end
  end
end

class TestStudioAbletonCLI < Minitest::Test
  def test_unified_cli_exports_inventory_composition_and_midi
    Dir.mktmpdir do |directory|
      source = TestAbletonLiveSetRecovery.allocate.write_set(directory)
      cli = File.expand_path("../bin/studio", __dir__)
      inventory_path = File.join(directory, "inventory.json")
      out, err, status = Open3.capture3(
        RbConfig.ruby, cli, "ableton", "inventory", directory, "--inventory", inventory_path
      )
      assert status.success?, "Studio inventory CLI failed: #{err}\n#{out}"
      inventory = JSON.parse(File.read(inventory_path))
      assert_equal 1, inventory.fetch("set_count")

      json_path = File.join(directory, "composition.json")
      ruby_path = File.join(directory, "composition.rb")
      out, err, status = Open3.capture3(
        RbConfig.ruby, cli, "ableton", "export", source, "--json", json_path, "--ruby", ruby_path
      )
      assert status.success?, "Studio export CLI failed: #{err}\n#{out}"
      assert_equal 3, JSON.parse(File.read(json_path)).fetch("tracks").length
      assert File.file?(ruby_path)

      midi_path = File.join(directory, "recovered.mid")
      out, err, status = Open3.capture3(
        RbConfig.ruby, cli, "ableton", "midi", source, "--out", midi_path
      )
      assert status.success?, "Studio MIDI CLI failed: #{err}\n#{out}"
      assert_equal "MThd", File.binread(midi_path, 4)
    end
  end

  def test_unknown_ableton_operation_fails_closed
    cli = File.expand_path("../bin/studio", __dir__)
    _out, err, status = Open3.capture3(RbConfig.ruby, cli, "ableton", "restore-everything")
    refute status.success?
    assert_match(/unknown Ableton operation/, err)
  end
end
