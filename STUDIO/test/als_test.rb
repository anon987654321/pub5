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
          <Tempo><Manual Value="93.5"/></Tempo>
          <TimeSignature><Numerator Value="4"/><Denominator Value="4"/></TimeSignature>
          <Tracks>
            <MidiTrack Id="10">
              <Name><EffectiveName Value="MIDI"/><UserName Value="Drums"/></Name>
              <DeviceChain><MainSequencer><ClipSlotList>
                <ClipSlot><ClipSlot>
                  <MidiClip Id="101" Time="4.0" Duration="8.0">
                    <Name><UserName Value="Drum phrase"/></Name>
                    <CurrentStart Value="0.0"/><CurrentEnd Value="8.0"/>
                    <Loop><LoopStart Value="0.0"/><LoopEnd Value="4.0"/><LoopOn Value="true"/></Loop>
                    <Notes><KeyTracks>
                      <KeyTrack><MidiKey Value="36"/><Notes>
                        <MidiNoteEvent NoteId="1" Time="0.5" Duration="0.25" Velocity="1.0" OffVelocity="0.4" IsEnabled="true"/>
                        <MidiNoteEvent NoteId="2" Time="1.0" Duration="0.5" Velocity="0.7" IsEnabled="false"/>
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
                        <MidiNoteEvent Time="0.0" Duration="1.0" Velocity="0.82" IsEnabled="true"/>
                      </Notes></KeyTrack>
                      <KeyTrack><MidiKey Value="64"/><Notes>
                        <MidiNoteEvent Time="0.0" Duration="1.0" Velocity="0.75" IsEnabled="true"/>
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
                    <Sample><FileRef><Name Value="break.wav"/><Path Value="Samples/Imported/break.wav"/><Type Value="2"/></FileRef></Sample>
                  </AudioClip>
                </ClipSlot></ClipSlot>
              </ClipSlotList></MainSequencer></DeviceChain>
            </AudioTrack>
          </Tracks>
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
      assert_equal [36, 36], drum_clip.fetch("notes").map { |note| note.fetch("pitch") }
      assert_equal false, drum_clip.fetch("notes").last.fetch("enabled")
      assert_equal 0.5, drum_clip.fetch("notes").first.fetch("start_beats")
    end
  end

  def test_accepts_extracted_plain_xml_for_diagnostics
    Dir.mktmpdir do |directory|
      project = Studio::ALS::Parser.new.parse(write_set(directory, compressed: false))
      assert_equal 3, project.fetch("tracks").length
      assert_equal "audio", project.fetch("tracks").last.fetch("kind")
      reference = project.fetch("tracks").last.fetch("clips").first.fetch("audio_references").first
      assert_equal "Samples/Imported/break.wav", reference.fetch("path")
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
      assert_includes bytes, [0x99, 36, 127].pack("C*") # channel 10 drum note-on
      assert_includes bytes, [0x81, 60, 104].pack("C*") # Rhodes on channel 2, note-off pair below
      assert_includes bytes, [0x81, 60, 0].pack("C*")
      refute_includes bytes, [0x99, 36, 89].pack("C*") # disabled note is excluded
    end
  end
end
