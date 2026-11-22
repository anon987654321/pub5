# frozen_string_literal: true

require_relative "../io/process_spawn"
require_relative "waveform"

module Master
  module Music
    # Minimal native synth: one waveform, one pitch, one duration, one file.
    class Synth
      RATE = 44_100
      SHAPES = %i[sine square triangle saw white brown].freeze
      NOISES = %i[white brown].freeze
      PLAYER_NAMES = %w[afplay play ffplay mpv aucat].freeze

      class NoPlayerError < StandardError; end

      class << self
        def render(shape: :sine, hz: 440.0, seconds: 1.0, destination: nil, seed: 42)
          shape = shape.to_sym
          validate_shape!(shape)
          destination ||= default_destination(shape)
          frames = (seconds * RATE).round
          samples = build_samples(shape, hz, frames, seed)
          Waveform.write_wav(destination, samples, rate: RATE)
        end

        # Start a finished audio file using the native player for this host.
        # SoX's file player is the `play` executable (not `sox input.wav`,
        # which has no output device argument). Try another installed player
        # when process creation fails; never report success without a PID.
        def play(path, loop: false)
          raise ArgumentError, "missing audio #{path}" unless File.file?(path)
          raise ArgumentError, "empty audio #{path}" unless File.size?(path)

          candidates = player_candidates(loop:)
          failures = []
          candidates.each do |argv|
            begin
              pid = Process.spawn(
                Master::Io::ProcessSpawn.environment, *argv, path,
                **Master::Io::ProcessSpawn.options(out: File::NULL, err: File::NULL),
              )
              # Leave the child waitable by the caller. A retained, unreaped child
              # PID cannot be recycled for an unrelated process while MASTER
              # still owns the playback handle.
              return pid
            rescue SystemCallError => e
              failures << "#{File.basename(argv.first)}: #{e.class}"
            end
          end

          tried = candidates.empty? ? PLAYER_NAMES.join(", ") : failures.join(", ")
          raise NoPlayerError, "no audio player could be started (tried #{tried})"
        end

        # Public: Realtime.morph generates frame-by-frame rather than as one
        # buffer, so it calls this directly instead of duplicating the four
        # waveform formulas.
        def oscillator(shape, hz, t)
          phase = (hz * t) % 1.0
          case shape
          when :square then phase < 0.5 ? 1.0 : -1.0
          when :triangle then phase < 0.5 ? 4.0 * phase - 1.0 : 3.0 - 4.0 * phase
          when :saw then 2.0 * phase - 1.0
          else Math.sin(2 * Math::PI * phase)
          end
        end

        # Public for the same reason: noise has no phase to compute from t, so
        # Realtime takes the whole run of it from here.
        def noise_samples(shape, frames, seed: 42) = noise(shape, frames, seed)

        private

        def player_candidates(loop:)
          names = loop ? %w[ffplay] : PLAYER_NAMES
          names.filter_map do |name|
            path = player_path(name)
            next unless path

            args = case name
                   when "afplay" then []
                   when "play" then %w[-q]
                   when "ffplay"
                     loop ? %w[-loop 0 -nodisp -autoexit -loglevel quiet -i] :
                            %w[-nodisp -autoexit -loglevel quiet -i]
                   when "mpv" then %w[--no-video --really-quiet]
                   when "aucat" then %w[-i]
                   else next
                   end
            [path, *args]
          end
        end

        def validate_shape!(shape)
          return if SHAPES.include?(shape)

          raise ArgumentError, "unknown shape #{shape}; valid: #{SHAPES.join(', ')}"
        end

        def player_path(name) = Master::Io::Exec.which(name, prefer: Master::Io::Exec::HOMEBREW_BINS)

        def default_destination(shape)
          File.expand_path("~/master-#{shape}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        end

        def build_samples(shape, hz, frames, seed)
          return noise(shape, frames, seed) if NOISES.include?(shape)

          Array.new(frames) { |i| oscillator(shape, hz, i.to_f / RATE) }
        end

        def noise(shape, frames, seed)
          rng = ::Random.new(seed)
          value = 0.0
          Array.new(frames) do
            raw = rng.rand * 2.0 - 1.0
            value = if shape == :white
                      raw
                    else
                      (value + 0.02 * raw).clamp(-1.0, 1.0)
                    end
            value * 0.8
          end
        end
      end
    end
  end
end
