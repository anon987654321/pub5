# frozen_string_literal: true

require "json"
require_relative "../io/exec"
require "yaml"

module Master
  module Voice
    # Audio-side regression checks. No ML dependency is required: ffprobe/ffmpeg
    # provide stable waveform facts, while optional aubio adds F0 when installed.
    # The tonem lane reads the same aubionotes stream with timestamps and scores
    # a pitch track against accent targets in data/voice/norwegian/ -
    # evaluation only, never a synthesis path.
    module Benchmark
      CONFIG_PATH = Master.data_path("tts_benchmark.yml")
      # tonem classification thresholds. The peak counts as early when it
      # lands in the first 40% of the voiced span and late from 60%; the
      # direction slope is measured on the first half of the voiced span.
      TONEM_EARLY_MAX = 0.40
      TONEM_LATE_MIN = 0.60
      # Hz per second: beyond this the first half is rising or falling,
      # inside it counts as level.
      DIRECTION_SLOPE_THRESHOLD = 20.0
      DEFAULT_CONFIG = {
        "min_score" => 75,
        "speech_rate_wpm" => { "min" => 105, "max" => 220 },
        "dynamic_range_db" => { "min" => 6 },
        "clipping_peak_db" => { "max" => -0.1 },
        "pause_ms" => { "min" => 70, "max" => 700 },
      }.freeze

      PROMPTS = [
        "Good morning. The answer is simple, but the interesting part comes next.",
        "Wait, really? Yes. That small detail changes everything.",
        "The key is not speed. It is rhythm, contrast, and knowing when to breathe.",
        "I can explain it clearly. First the result, then the reason, and finally the catch.",
        "Be careful here: a technically correct voice can still sound completely lifeless.",
        "Imagine this sentence slowing down just before the reveal. That tiny pause matters.",
        "Now we move from the practical answer to the deeper idea behind it.",
        "Sometimes a short answer should be short. No theatrical pause is needed.",
        "And then, unexpectedly, the voice should lift a little before landing.",
        "The final point is this: consistency should feel human, not mechanical.",
      ].freeze

      module_function

      def config
        raw = File.exist?(CONFIG_PATH) ? YAML.safe_load(File.read(CONFIG_PATH)) : {}
        DEFAULT_CONFIG.merge(raw.is_a?(Hash) ? raw.fetch("benchmark", {}) : {})
      rescue StandardError
        DEFAULT_CONFIG
      end

      def available?
        executable?("ffprobe") && executable?("ffmpeg")
      end

      def analyze(path, words: nil)
        return { path:, available: false } unless available? && File.file?(path)

        duration = probe_duration(path)
        silence = silence_profile(path)
        rms = rms_profile(path)
        result = {
          path:,
          available: true,
          duration_s: duration,
          silence:,
          rms:,
          speech_rate_wpm: speech_rate(words, duration),
          clipped: rms[:peak_db] >= -0.1,
          dynamic_range_db: rms[:peak_db] - rms[:rms_db],
        }

        f0 = aubio_pitch(path)
        result[:f0] = f0 if f0
        result
      end

      def score(metrics, text:)
        checks = []
        checks << [:audio_present, metrics[:duration_s].to_f > 0.25]
        checks << [:not_clipped, !metrics[:clipped]]
        checks << [:dynamic_range, metrics[:dynamic_range_db].to_f >= config.dig("dynamic_range_db", "min").to_f]
        checks << [:rhythm, metrics.dig(:silence, :count).to_i.zero? || metrics.dig(:silence, :mean_ms).to_f.between?(config.dig("pause_ms", "min").to_f, config.dig("pause_ms", "max").to_f)]

        words = text.to_s.split.size
        rate = metrics[:speech_rate_wpm].to_f
        checks << [:speech_rate, rate.zero? || rate.between?(config.dig("speech_rate_wpm", "min").to_f, config.dig("speech_rate_wpm", "max").to_f)]

        passed = checks.count { |_, ok| ok }
        {
          score: ((passed.to_f / checks.length) * 100).round(1),
          checks: checks.to_h,
          passed:,
          total: checks.length,
        }
      end

      def torture_prompts
        PROMPTS
      end

      def probe_duration(path)
        out, _err, status = Master::Io::Exec.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1", path
        )
        status.success? ? out.to_f : 0.0
      end

      def silence_profile(path)
        out, err, status = Master::Io::Exec.capture3(
          "ffmpeg", "-hide_banner", "-i", path.to_s, "-af",
          "silencedetect=noise=-42dB:d=0.07", "-f", "null", "-"
        )
        trace = "#{out}\n#{err}"
        return { count: 0, mean_ms: 0.0, max_ms: 0.0 } unless status.success? || !trace.empty?

        durations = trace.scan(/silence_duration:\s*([0-9.]+)/).flatten.map { |v| v.to_f * 1000 }
        {
          count: durations.length,
          mean_ms: durations.empty? ? 0.0 : durations.sum / durations.length,
          max_ms: durations.max.to_f,
        }
      rescue StandardError
        { count: 0, mean_ms: 0.0, max_ms: 0.0 }
      end

      def rms_profile(path)
        out, err, _status = Master::Io::Exec.capture3(
          "ffmpeg", "-hide_banner", "-i", path.to_s,
          "-af", "volumedetect", "-f", "null", "-"
        )
        trace = "#{out}\n#{err}"
        peak = trace[/max_volume:\s*(-?[0-9.]+) dB/, 1].to_f
        rms = trace[/mean_volume:\s*(-?[0-9.]+) dB/, 1].to_f
        { peak_db: peak, rms_db: rms }
      rescue StandardError
        { peak_db: -99.0, rms_db: -99.0 }
      end

      def speech_rate(words, duration)
        return 0.0 unless words.to_i.positive? && duration.to_f.positive?

        words.to_f / duration.to_f * 60.0
      end

      def aubio_pitch(path)
        track = pitch_track(path)
        return unless track

        values = track.map { |point| point[:hz] }
        {
          min_hz: values.min.round(1),
          max_hz: values.max.round(1),
          mean_hz: (values.sum / values.length).round(1),
          range_hz: (values.max - values.min).round(1),
        }
      end

      # The same aubionotes stream the f0 summary reads, kept as a timed
      # track: one { t:, hz: } point per note line. Answers nil when aubio
      # is missing, the call fails, or nothing voiced survives the 50-500 Hz
      # gate - callers treat nil as "no verdict", never an error.
      def pitch_track(path)
        return unless executable?("aubionotes")

        out, _err, status = Master::Io::Exec.capture3(
          "aubionotes", "-i", path.to_s, "-t", "0.2"
        )
        return unless status.success?

        track = out.lines.filter_map do |line|
          columns = line.split
          next unless columns.length >= 2

          t = columns[0].to_f
          hz = columns[1].to_f
          { t: t, hz: hz } if t >= 0 && hz.between?(50, 500)
        end
        return if track.empty?

        track
      rescue StandardError
        nil
      end

      # Peak position inside the voiced span. Early means the tonem-1 high
      # point lands near the stressed-vowel onset (Bergen); late is the
      # delayed alignment.
      def classify_peak_timing(track)
        return nil unless track.is_a?(Array) && track.length >= 2

        t_first = track.first[:t].to_f
        span = track.last[:t].to_f - t_first
        return nil if span <= 0

        peak = track.max_by { |point| point[:hz] }
        peak_rel = (peak[:t].to_f - t_first) / span
        if peak_rel <= TONEM_EARLY_MAX
          :early
        elsif peak_rel >= TONEM_LATE_MIN
          :late
        else
          :mid
        end
      rescue StandardError
        nil
      end

      # Direction of the first half of the voiced span, as a least-squares
      # slope in Hz/s. This is where a tonem-1 fall separates itself from an
      # eastern low or rising onset.
      def classify_direction(track)
        return nil unless track.is_a?(Array) && track.length >= 2

        t_first = track.first[:t].to_f
        span = track.last[:t].to_f - t_first
        return nil if span <= 0

        half = track.select { |point| point[:t].to_f <= t_first + span / 2 }
        return nil if half.length < 2

        slope = least_squares_slope(half)
        return nil if slope.nil?

        if slope < -DIRECTION_SLOPE_THRESHOLD
          :falling
        elsif slope > DIRECTION_SLOPE_THRESHOLD
          :rising
        else
          :level
        end
      rescue StandardError
        nil
      end

      def least_squares_slope(points)
        n = points.length.to_f
        sum_x = points.sum { |p| p[:t].to_f }
        sum_y = points.sum { |p| p[:hz].to_f }
        sum_xy = points.sum { |p| p[:t].to_f * p[:hz].to_f }
        sum_x2 = points.sum { |p| p[:t].to_f ** 2 }
        denominator = n * sum_x2 - (sum_x**2)
        return nil if denominator.abs < 1e-9

        (n * sum_xy - sum_x * sum_y) / denominator
      end

      # Accent targets from the evaluation fixtures. Unknown accent or an
      # unparseable target answers nil - fail closed, never guessed.
      def tonem_target(accent)
        path = Master.data_path("voice", "norwegian", "#{accent}.yml")
        return unless File.file?(path)

        raw = YAML.safe_load(File.read(path))
        targets = raw.is_a?(Hash) ? raw.dig("evaluation", "f0_targets") : nil
        return unless targets

        peak_timing = { "early" => :early, "low_or_rising" => :low_or_rising }[targets["tonem1_peak"].to_s]
        direction = { "falling" => :falling, "rising_or_level" => :rising_or_level }[targets["tonem1_direction"].to_s]
        return unless peak_timing && direction

        { peak_timing:, direction:, accent: accent.to_s }
      rescue StandardError
        nil
      end

      # Score a pitch track against a tonem target. Two checks - peak
      # placement and first-half direction - averaged; 0.6 or better passes.
      # A track with neither measurement class answers nil.
      def tonem_verdict(track, target)
        peak_class = classify_peak_timing(track)
        direction = classify_direction(track)
        return nil if peak_class.nil? && direction.nil?

        peak_check =
          case target[:peak_timing]
          when :early
            peak_class == :early ? 1.0 : (peak_class == :mid ? 0.5 : 0.0)
          when :low_or_rising
            peak_class.nil? || peak_class == :early ? 0.0 : 1.0
          else
            0.0
          end

        direction_check =
          case target[:direction]
          when :falling
            direction == :falling ? 1.0 : (direction == :level ? 0.3 : 0.0)
          when :rising_or_level
            direction == :rising || direction == :level ? 1.0 : (direction.nil? ? 0.5 : 0.2)
          else
            0.0
          end

        score = ((peak_check + direction_check) / 2).round(3)
        {
          target:,
          measured: {
            peak_timing_class: peak_class,
            direction:,
          },
          score:,
          pass: score >= 0.6,
        }
      end

      # The tonem lane entry point: pitch track in, verdict out. Nil means
      # "no verdict" - missing aubio, unreadable audio, unknown accent -
      # and never an exception.
      def tonem_eval(path, accent: "bergen")
        target = tonem_target(accent)
        return unless target

        track = pitch_track(path)
        return unless track

        verdict = tonem_verdict(track, target)
        return unless verdict

        verdict.merge(path: path, accent: accent.to_s, available: true)
      end

      def executable?(name)
        Master::Io::Exec.on_path?(name)
      end
    end
  end
end
