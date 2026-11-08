# frozen_string_literal: true

require "fileutils"
require_relative "als"

module Studio
  module ALS
    class MidiExporter
      DEFAULT_PPQN = 960
      DRUM_TRACK = /drum|kit|beat/i

      def initialize(ppqn: DEFAULT_PPQN)
        @ppqn = Integer(ppqn)
        raise ArgumentError, "PPQN must be between 24 and 32767" unless @ppqn.between?(24, 32_767)
      end

      def write(project, path)
        midi_tracks = Array(project["tracks"]).select { |track| track["kind"] == "midi" }
        tempo = project["tempo_bpm"].to_f
        tempo = 120.0 unless tempo.positive?
        track_chunks = [tempo_track(tempo, project["time_signature"])]
        midi_tracks.each_with_index do |track, index|
          channel = DRUM_TRACK.match?(track["name"].to_s) ? 9 : melodic_channel(index)
          track_chunks << instrument_track(track, channel)
        end
        header = "MThd".b + [6, 1, track_chunks.length, @ppqn].pack("Nnnn")
        write_atomic(path, header + track_chunks.join)
      end

      private

      def melodic_channel(index)
        candidate = index % 9
        candidate
      end

      def instrument_track(track, channel)
        rows = []
        Array(track["clips"]).each do |clip|
          clip_start = clip["start_beats"].to_f
          clip_length = clip["length_beats"].to_f
          loop_start = clip["loop_start_beats"].to_f
          loop_end = clip["loop_end_beats"].to_f
          loop_length = loop_end - loop_start
          looping = clip["loop_enabled"] == true && loop_length.positive?
          Array(clip["notes"]).each do |note|
            next if note["enabled"] == false
            next if note["pitch"].nil?

            local_start = note["start_beats"].to_f
            duration = [note["duration_beats"].to_f, 1.0 / @ppqn].max
            positions = if looping && clip_length.positive?
                          repeated_positions(local_start, clip_length, loop_length)
                        else
                          [local_start]
                        end
            positions.each do |position|
              start_beat = clip_start + position
              rows.concat(note_events(start_beat, duration, note, channel))
            end
          end
        end
        track_chunk(track["name"].to_s, rows)
      end

      def repeated_positions(note_start, clip_length, loop_length)
        return [note_start] unless loop_length.positive?

        positions = []
        offset = 0.0
        while note_start + offset < clip_length
          positions << (note_start + offset)
          offset += loop_length
          raise ParseError, "clip loop expansion exceeds 100000 note instances" if positions.length > 100_000
        end
        positions
      end

      def note_events(start_beat, duration_beats, note, channel)
        start_tick = [(start_beat * @ppqn).round, 0].max
        end_tick = [( (start_beat + duration_beats) * @ppqn).round, start_tick + 1].max
        pitch = note["pitch"].to_i.clamp(0, 127)
        velocity = (note["velocity"].to_f * 127).round.clamp(1, 127)
        [
          [start_tick, 1, [0x90 | channel, pitch, velocity].pack("C*")],
          [end_tick, 0, [0x80 | channel, pitch, 0].pack("C*")]
        ]
      end

      def tempo_track(bpm, time_signature)
        microseconds = (60_000_000.0 / bpm).round
        tempo = [0xff, 0x51, 0x03, (microseconds >> 16) & 0xff,
                 (microseconds >> 8) & 0xff, microseconds & 0xff].pack("C*")
        numerator = (time_signature && time_signature["numerator"] || 4).to_i.clamp(1, 32)
        denominator = (time_signature && time_signature["denominator"] || 4).to_i.clamp(1, 32)
        denominator_power = Math.log2(denominator).round.clamp(0, 7)
        signature = [0xff, 0x58, 0x04, numerator, denominator_power, 24, 8].pack("C*")
        track_chunk("Tempo", [[0, -1, tempo], [0, -1, signature]])
      end

      def track_chunk(name, rows)
        events = [[0, -2, meta_text(name)]]
        events.concat(rows)
        events.sort_by! { |tick, priority, _bytes| [tick, priority] }
        body = String.new(encoding: Encoding::BINARY)
        previous = 0
        events.each do |tick, _priority, bytes|
          body << variable_length([tick - previous, 0].max)
          body << bytes
          previous = tick
        end
        body << "\x00\xff\x2f\x00".b
        "MTrk".b + [body.bytesize].pack("N") + body
      end

      def meta_text(name)
        text = name.to_s.b
        [0xff, 0x03, text.bytesize].pack("C*") + text
      end

      def variable_length(value)
        buffer = value.to_i & 0x7f
        remaining = value.to_i >> 7
        while remaining.positive?
          buffer = (buffer << 8) | ((remaining & 0x7f) | 0x80)
          remaining >>= 7
        end
        bytes = String.new(encoding: Encoding::BINARY)
        loop do
          byte = buffer & 0xff
          bytes << byte
          break if (byte & 0x80).zero?
          buffer >>= 8
        end
        bytes
      end

      def write_atomic(path, bytes)
        destination = File.expand_path(path)
        FileUtils.mkdir_p(File.dirname(destination))
        temporary = "#{destination}.tmp-#{Process.pid}"
        File.binwrite(temporary, bytes)
        File.rename(temporary, destination)
        destination
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  input = ARGV.shift
  abort "usage: ruby als_to_midi.rb SET.als [--out PATH] [--ppqn 960]" unless input

  base = File.join(File.dirname(File.expand_path(input)), File.basename(input, File.extname(input)))
  output = "#{base}.mid"
  ppqn = Studio::ALS::MidiExporter::DEFAULT_PPQN
  OptionParser.new do |parser|
    parser.on("--out PATH", "MIDI output path") { |value| output = value }
    parser.on("--ppqn N", Integer, "ticks per quarter note (24..32767)") { |value| ppqn = value }
  end.parse!(ARGV)

  project = Studio::ALS::Parser.new.parse(input)
  result = Studio::ALS::MidiExporter.new(ppqn:).write(project, output)
  count = Array(project["tracks"]).count { |track| track["kind"] == "midi" }
  puts "als-midi: #{count} MIDI tracks written to #{result}"
end
