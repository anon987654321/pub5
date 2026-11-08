# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "als"

module Studio
  module ALS
    class AudioRenderError < StandardError; end

    # Optional offline audio bridge. It invokes local binaries with argv arrays
    # (never a shell string) and keeps the neutral FluidSynth render untouched.
    class AudioRenderer
      DEFAULT_SAMPLE_RATE = 44_100
      DEFAULT_ANALOG_FILTERS = "asoftclip=type=tanh:threshold=0.92:output=0.96,vibrato=f=4.7:d=0.035,lowpass=f=15000"

      def initialize(fluidsynth: "fluidsynth", ffmpeg: "ffmpeg", sample_rate: DEFAULT_SAMPLE_RATE)
        @fluidsynth = fluidsynth
        @ffmpeg = ffmpeg
        @sample_rate = Integer(sample_rate)
        raise ArgumentError, "sample rate must be between 22050 and 192000" unless @sample_rate.between?(22_050, 192_000)
      end

      def render(midi_path:, soundfont:, wav_path:, analog: false, analog_path: nil)
        raise AudioRenderError, "MIDI file does not exist: #{midi_path}" unless File.file?(midi_path)
        raise AudioRenderError, "SoundFont file does not exist: #{soundfont}" unless File.file?(soundfont)

        destination = File.expand_path(wav_path)
        FileUtils.mkdir_p(File.dirname(destination))
        command = [
          @fluidsynth, "-ni", "-r", @sample_rate.to_s, "-F", destination,
          "-T", "wav", soundfont, midi_path
        ]
        run!(command, "FluidSynth")
        raise AudioRenderError, "FluidSynth did not create #{destination}" unless File.file?(destination)

        result = { wav: destination }
        if analog
          processed = File.expand_path(analog_path || destination.sub(/\.wav\z/i, "") + "-analog.wav")
          FileUtils.mkdir_p(File.dirname(processed))
          run!([@ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", destination,
                "-af", DEFAULT_ANALOG_FILTERS, processed], "FFmpeg analog chain")
          raise AudioRenderError, "FFmpeg did not create #{processed}" unless File.file?(processed)
          result[:analog_wav] = processed
        end
        result
      end

      private

      def run!(command, label)
        _stdout, stderr, status = Open3.capture3(*command)
        return if status.success?

        raise AudioRenderError, "#{label} failed (#{status.exitstatus}): #{stderr.to_s.lines.last(8).join.strip}"
      rescue Errno::ENOENT => error
        raise AudioRenderError, "#{label} executable not found (#{command.first.inspect}): #{error.message}"
      end
    end

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

      # Allocate every melodic channel except zero-based channel 9, which is
      # reserved for General MIDI percussion. Reuse only after 15 instruments.
      def melodic_channel(index)
        candidate = index % 15
        candidate >= 9 ? candidate + 1 : candidate
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
                          repeated_positions(local_start, clip_length, loop_start, loop_end)
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

      def repeated_positions(note_start, clip_length, loop_start, loop_end)
        loop_length = loop_end - loop_start
        # Notes before the loop start are pickups. Notes outside the loop
        # window remain one-shots; only notes inside it repeat.
        return [note_start] unless loop_length.positive?
        return [note_start] if note_start < loop_start || note_start >= loop_end

        positions = []
        position = note_start
        while position < clip_length
          positions << position
          position += loop_length
          raise ParseError, "clip loop expansion exceeds 100000 note instances" if positions.length > 100_000
        end
        positions
      end

      def note_events(start_beat, duration_beats, note, channel)
        start_tick = [(start_beat * @ppqn).round, 0].max
        end_tick = [( (start_beat + duration_beats) * @ppqn).round, start_tick + 1].max
        pitch = note["pitch"].to_i.clamp(0, 127)
        source_velocity = note.key?("velocity_raw") && !note["velocity_raw"].nil? ? note["velocity_raw"].to_f : note["velocity"].to_f * 127.0
        velocity = source_velocity.round.clamp(1, 127)
        release_velocity = note["release_velocity"] ? note["release_velocity"].to_f.round.clamp(0, 127) : 0
        [
          [start_tick, 1, [0x90 | channel, pitch, velocity].pack("C*")],
          [end_tick, 0, [0x80 | channel, pitch, release_velocity].pack("C*")]
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
  abort "usage: ruby als_to_midi.rb SET.als [--out PATH] [--ppqn 960] [--wav PATH --soundfont FILE.sf2] [--analog]" unless input

  base = File.join(File.dirname(File.expand_path(input)), File.basename(input, File.extname(input)))
  output = "#{base}.mid"
  wav_path = nil
  soundfont = nil
  analog = false
  analog_path = nil
  ppqn = Studio::ALS::MidiExporter::DEFAULT_PPQN
  fluidsynth = "fluidsynth"
  ffmpeg = "ffmpeg"
  sample_rate = Studio::ALS::AudioRenderer::DEFAULT_SAMPLE_RATE
  OptionParser.new do |parser|
    parser.on("--out PATH", "MIDI output path") { |value| output = value }
    parser.on("--ppqn N", Integer, "ticks per quarter note (24..32767)") { |value| ppqn = value }
    parser.on("--wav PATH", "Render MIDI to WAV with FluidSynth") { |value| wav_path = value }
    parser.on("--soundfont PATH", "SoundFont required for --wav") { |value| soundfont = value }
    parser.on("--analog", "Apply optional FFmpeg soft-clip/vibrato/low-pass chain") { analog = true }
    parser.on("--analog-out PATH", "Processed WAV destination (defaults to *-analog.wav)") { |value| analog_path = value }
    parser.on("--fluidsynth BIN", "FluidSynth executable") { |value| fluidsynth = value }
    parser.on("--ffmpeg BIN", "FFmpeg executable") { |value| ffmpeg = value }
    parser.on("--sample-rate N", Integer, "FluidSynth output rate") { |value| sample_rate = value }
  end.parse!(ARGV)

  project = Studio::ALS::Parser.new.parse(input)
  result = Studio::ALS::MidiExporter.new(ppqn:).write(project, output)
  count = Array(project["tracks"]).count { |track| track["kind"] == "midi" }
  puts "als-midi: #{count} MIDI tracks written to #{result}"
  if wav_path
    abort "als-midi: --soundfont is required with --wav" unless soundfont
    audio = Studio::ALS::AudioRenderer.new(fluidsynth:, ffmpeg:, sample_rate:).render(
      midi_path: result, soundfont:, wav_path:, analog:, analog_path:
    )
    puts "als-audio: #{audio.fetch(:wav)}"
    puts "als-audio: #{audio.fetch(:analog_wav)}" if audio[:analog_wav]
  elsif soundfont || analog || analog_path
    abort "als-midi: --soundfont/--analog options require --wav"
  end
end
