# frozen_string_literal: true

require "json"
require "optparse"
require "fileutils"

module Studio
  module DillaReference
    class AnalysisError < StandardError; end

    # Dependency-free spectral analysis for Dilla's reference pipeline.
    # WAV decoding, resampling, FFT, onset analysis and harmony estimation all
    # live here; there is no Python, NumPy, SciPy or native-gem requirement.
    class Analyzer
      SAMPLE_RATE = 22_050
      HOP = 512
      FFT_SIZE = 1_024
      BIN_COUNT = (FFT_SIZE / 2) + 1
      FRAME_SECONDS = HOP.to_f / SAMPLE_RATE
      MAX_FILE_BYTES = 256 * 1024 * 1024
      MAX_SECONDS = 600

      KRUM_MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88].freeze
      KRUM_MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17].freeze
      PC_SHARP = %w[C C# D D# E F F# G G# A A# B].freeze
      PC_FLAT = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
      FLAT_BIAS = [5, 7, 10, 8, 3, 1].freeze
      CHORD_QUALITIES = {
        "maj" => [0, 4, 7], "min" => [0, 3, 7],
        "7" => [0, 4, 7, 10], "m7" => [0, 3, 7, 10]
      }.freeze

      def analyze(path, stems_dir: nil, max_duration: nil)
        duration_limit = normalize_duration(max_duration)
        mono = read_wav(path, max_duration: duration_limit)
        raise AnalysisError, "audio is too short for spectral analysis (need at least #{FFT_SIZE} samples)" if mono.length < FFT_SIZE

        frequencies, spectra = stft(mono)
        flux = spectral_flux(spectra)
        _onsets, envelope = pick_onsets(flux)
        bpm, confidence = estimate_tempo(envelope)
        phase = beat_phase(envelope, bpm)

        drums_spectra = nil
        if stems_dir && File.directory?(stems_dir)
          drums_path = File.join(stems_dir, "drums.wav")
          drums_mono = read_wav(drums_path, max_duration: duration_limit) if File.file?(drums_path)
          drums_spectra = stft(drums_mono).last if drums_mono && drums_mono.length >= FFT_SIZE
        end

        drum_onsets = if drums_spectra
                        drum_indices = indices_for(frequencies, 30, 9_000)
                        pick_onsets(spectral_flux(drums_spectra, drum_indices)).first
                      else
                        band_indices = indices_for(frequencies, [[30, 160], [150, 700], [4_000, 12_000]])
                        pick_onsets(spectral_flux(spectra, band_indices)).first
                      end

        features = { "duration_s" => round(mono.length.to_f / SAMPLE_RATE, 2) }
        features.merge!(grid_features(drum_onsets, envelope, bpm, phase))
        features["bpm"] = round(bpm, 2)
        features["bpm_confidence"] = round(confidence, 3)

        shares = stems_dir ? energy_shares(stems_dir, duration_limit) : nil
        features.merge!(shares || band_shares_from_mix(spectra, frequencies))

        mean_magnitude = mean_spectrum(spectra)
        total_magnitude = mean_magnitude.sum
        brightness = total_magnitude.positive? ? mean_magnitude.each_with_index.sum { |v, i| v * frequencies[i] } / total_magnitude : 0.0
        features["brightness_hz"] = round(brightness, 1)

        chroma = chroma_of(mean_power_spectrum(spectra), frequencies)
        key, key_score = estimate_key(chroma)
        chroma_frames = spectra.each_slice(22).filter_map do |slice|
          chroma_of(mean_power_spectrum(slice), frequencies) if slice.length > 4
        end
        chroma_frames = [chroma] if chroma_frames.empty?
        harmony = { "key" => key, "key_confidence" => round(key_score, 3) }
        harmony.merge!(chord_changes(chroma_frames, 1.0 / (22 * FRAME_SECONDS)))
        features["harmony"] = harmony
        features["melody"] = melody_summary(spectra, frequencies, bpm)
        features["drum_grid"] = drum_grids(spectra, frequencies, drums_spectra, bpm, phase)
        features["sections"] = sections_of(mono, bpm)
        clean_numbers(features)
      rescue Errno::ENOENT => error
        raise AnalysisError, error.message
      end

      def write(path, output, **options)
        features = analyze(path, **options)
        write_atomic(output, JSON.pretty_generate(sort_hashes(features)) + "\n")
        features
      end

      private

      def normalize_duration(value)
        return MAX_SECONDS if value.nil? || value.to_f <= 0

        seconds = Float(value)
        raise AnalysisError, "max duration must be finite" unless seconds.finite?
        raise AnalysisError, "max duration must not exceed #{MAX_SECONDS} seconds" if seconds > MAX_SECONDS

        seconds
      end

      def read_wav(path, max_duration: nil)
        file = File.expand_path(path)
        raise AnalysisError, "audio file does not exist: #{file}" unless File.file?(file)
        size = File.size(file)
        raise AnalysisError, "audio file exceeds #{MAX_FILE_BYTES} bytes" if size > MAX_FILE_BYTES
        bytes = File.binread(file)
        raise AnalysisError, "not a RIFF/WAVE file: #{file}" unless bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WAVE"

        format = channels = sample_rate = bits = nil
        data = nil
        offset = 12
        while offset + 8 <= bytes.bytesize
          id = bytes.byteslice(offset, 4)
          length = bytes.byteslice(offset + 4, 4).unpack1("V")
          payload = bytes.byteslice(offset + 8, length)
          raise AnalysisError, "truncated WAV chunk #{id.inspect}" unless payload && payload.bytesize == length

          case id
          when "fmt "
            raise AnalysisError, "WAV fmt chunk is too short" if payload.bytesize < 16
            format, channels, sample_rate = payload.unpack("vvV")
            bits = payload.byteslice(14, 2).unpack1("v")
            format = payload.byteslice(24, 2).unpack1("v") if format == 0xfffe && payload.bytesize >= 40
          when "data"
            data = payload
          end
          offset += 8 + length + (length.odd? ? 1 : 0)
        end

        raise AnalysisError, "WAV is missing fmt or data chunks" unless format && data
        raise AnalysisError, "invalid WAV channel count" unless channels.to_i.between?(1, 32)
        raise AnalysisError, "invalid WAV sample rate" unless sample_rate.to_i.between?(4_000, 384_000)
        samples = decode_pcm(data, format, bits, channels)
        samples = samples.first((max_duration * sample_rate).floor) if max_duration
        raise AnalysisError, "audio contains no complete samples" if samples.empty?
        samples = resample(samples, sample_rate) unless sample_rate == SAMPLE_RATE
        samples
      end

      def decode_pcm(data, format, bits, channels)
        samples = case [format, bits]
                  when [1, 8]
                    data.unpack("C*").map { |v| (v - 128) / 128.0 }
                  when [1, 16]
                    data.unpack("s<*").map { |v| v / 32_768.0 }
                  when [1, 24]
                    decode_24bit(data)
                  when [1, 32]
                    data.unpack("l<*").map { |v| v / 2_147_483_648.0 }
                  when [3, 32]
                    data.unpack("e*")
                  when [3, 64]
                    data.unpack("E*")
                  else
                    raise AnalysisError, "unsupported WAV encoding format=#{format} bits=#{bits}"
                  end
        frame_size = channels * (bits / 8)
        raise AnalysisError, "WAV data ends in a partial sample frame" unless (data.bytesize % frame_size).zero?

        samples.each_slice(channels).map do |frame|
          value = frame.sum / channels.to_f
          value.finite? ? value.clamp(-1.0, 1.0) : 0.0
        end
      end

      def decode_24bit(data)
        values = []
        index = 0
        while index + 2 < data.bytesize
          value = data.getbyte(index) | (data.getbyte(index + 1) << 8) | (data.getbyte(index + 2) << 16)
          value -= 1 << 24 if (value & (1 << 23)).positive?
          values << value / 8_388_608.0
          index += 3
        end
        values
      end

      def resample(samples, source_rate)
        output_length = (samples.length * SAMPLE_RATE.to_f / source_rate).round
        return samples if output_length == samples.length
        if source_rate == SAMPLE_RATE * 2
          return samples.each_slice(2).map { |pair| pair.sum / pair.length.to_f }.first(output_length)
        end

        # Windowed-sinc interpolation suppresses aliasing on uncommon sample
        # rates while keeping the common 44.1 kHz path cheap above.
        radius = 8
        cutoff = [SAMPLE_RATE.to_f / source_rate, 1.0].min * 0.94
        Array.new(output_length) do |out_index|
          position = out_index * source_rate.to_f / SAMPLE_RATE
          center = position.floor
          weighted = total_weight = 0.0
          (-radius + 1..radius).each do |delta|
            index = center + delta
            next unless index.between?(0, samples.length - 1)

            distance = position - index
            x = cutoff * distance
            sinc = x.abs < 1e-12 ? 1.0 : Math.sin(Math::PI * x) / (Math::PI * x)
            window_position = distance / radius.to_f
            next if window_position.abs >= 1.0

            window = 0.5 + 0.5 * Math.cos(Math::PI * window_position)
            weight = cutoff * sinc * window
            weighted += samples[index] * weight
            total_weight += weight
          end
          total_weight.abs < 1e-12 ? 0.0 : weighted / total_weight
        end
      end

      def stft(samples)
        frame_count = 1 + ((samples.length - FFT_SIZE) / HOP)
        window = Array.new(FFT_SIZE) { |i| 0.5 - 0.5 * Math.cos(2.0 * Math::PI * i / (FFT_SIZE - 1)) }
        window_sum = window.sum
        frequencies = Array.new(BIN_COUNT) { |i| i * SAMPLE_RATE.to_f / FFT_SIZE }
        spectra = Array.new(frame_count)
        frame_count.times do |frame|
          start = frame * HOP
          real = Array.new(FFT_SIZE, 0.0)
          imag = Array.new(FFT_SIZE, 0.0)
          FFT_SIZE.times { |i| real[i] = (samples[start + i] || 0.0) * window[i] }
          fft!(real, imag)
          spectra[frame] = Array.new(BIN_COUNT) do |bin|
            Math.sqrt(real[bin] * real[bin] + imag[bin] * imag[bin]) / window_sum
          end
        end
        [frequencies, spectra]
      end

      def fft!(real, imag)
        n = real.length
        j = 0
        i = 1
        while i < n
          bit = n >> 1
          while (j & bit).positive?
            j ^= bit
            bit >>= 1
          end
          j ^= bit
          if i < j
            real[i], real[j] = real[j], real[i]
            imag[i], imag[j] = imag[j], imag[i]
          end
          i += 1
        end

        length = 2
        while length <= n
          angle = -2.0 * Math::PI / length
          w_length_real = Math.cos(angle)
          w_length_imag = Math.sin(angle)
          half = length / 2
          start = 0
          while start < n
            w_real = 1.0
            w_imag = 0.0
            half.times do |offset|
              even = start + offset
              odd = even + half
              odd_real = real[odd] * w_real - imag[odd] * w_imag
              odd_imag = real[odd] * w_imag + imag[odd] * w_real
              real[odd] = real[even] - odd_real
              imag[odd] = imag[even] - odd_imag
              real[even] += odd_real
              imag[even] += odd_imag
              next_real = w_real * w_length_real - w_imag * w_length_imag
              w_imag = w_real * w_length_imag + w_imag * w_length_real
              w_real = next_real
            end
            start += length
          end
          length <<= 1
        end
      end

      def mean_spectrum(spectra)
        result = Array.new(BIN_COUNT, 0.0)
        spectra.each do |frame|
          BIN_COUNT.times { |i| result[i] += frame[i] }
        end
        divisor = [spectra.length, 1].max.to_f
        result.map! { |value| value / divisor }
      end

      def mean_power_spectrum(spectra)
        result = Array.new(BIN_COUNT, 0.0)
        spectra.each do |frame|
          BIN_COUNT.times { |i| result[i] += frame[i] * frame[i] }
        end
        divisor = [spectra.length, 1].max.to_f
        result.map! { |value| value / divisor }
      end

      def spectral_flux(spectra, indices = nil)
        selected = indices || (0...BIN_COUNT).to_a
        previous = nil
        spectra.map do |frame|
          flux = 0.0
          if previous
            selected.each do |bin|
              difference = frame[bin] - previous[bin]
              flux += difference if difference.positive?
            end
          end
          previous = frame
          flux
        end
      end

      def indices_for(frequencies, lower, upper = nil)
        ranges = lower.is_a?(Array) ? lower : [[lower, upper]]
        frequencies.each_index.select do |index|
          ranges.any? { |lo, hi| frequencies[index] >= lo && frequencies[index] <= hi }
        end
      end

      def pick_onsets(flux)
        env = flux.zip(median_filter(flux, 31)).map { |value, median| [value - median, 0.0].max }
        maximum = env.max || 0.0
        return [[], env] unless maximum.positive?

        gate = [maximum * 0.14, percentile(env, 92)].max
        distance = [(0.085 / FRAME_SECONDS).to_i, 1].max
        peaks = find_peaks(env, height: gate, distance: distance)
        return [[], env] if peaks.empty?

        log_env = env.map { |value| Math.log(value + 1e-9) }
        refined = peaks.map do |peak|
          if peak.positive? && peak < log_env.length - 1
            a, b, c = log_env[peak - 1], log_env[peak], log_env[peak + 1]
            denominator = a - (2.0 * b) + c
            shift = denominator.abs > 1e-9 ? (0.5 * (a - c) / denominator).clamp(-0.5, 0.5) : 0.0
            peak + shift
          else
            peak.to_f
          end
        end
        [refined, env]
      end

      def median_filter(values, width)
        radius = width / 2
        values.each_index.map do |index|
          sample = []
          (-radius).upto(radius) do |offset|
            position = index + offset
            sample << (position.negative? || position >= values.length ? 0.0 : values[position])
          end
          sample.sort[radius]
        end
      end

      def percentile(values, percent)
        return 0.0 if values.empty?

        ordered = values.sort
        position = (percent / 100.0) * (ordered.length - 1)
        lower = position.floor
        upper = position.ceil
        ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)
      end

      def find_peaks(values, height:, distance: 1)
        candidates = []
        (1...(values.length - 1)).each do |index|
          next unless values[index] >= height && values[index] > values[index - 1] && values[index] >= values[index + 1]

          candidates << index
        end
        selected = []
        candidates.sort_by { |index| -values[index] }.each do |index|
          selected << index unless selected.any? { |other| (other - index).abs < distance }
        end
        selected.sort
      end

      def estimate_tempo(env)
        n = env.length
        return [90.0, 0.0] if n < 64

        mean = env.sum / n.to_f
        centered = env.map { |value| value - mean }
        autocorrelation_zero = centered.sum { |value| value * value }
        return [90.0, 0.0] if autocorrelation_zero <= 1e-12

        fps = 1.0 / FRAME_SECONDS
        lower_lag = [(fps * 60.0 / 200.0).to_i, 1].max
        upper_lag = [((fps * 60.0 / 40.0).to_i), n - 1].min
        return [90.0, 0.0] if upper_lag <= lower_lag

        correlations = {}
        best_lag = lower_lag
        best_strength = -Float::INFINITY
        lower_lag.upto(upper_lag - 1) do |lag|
          sum = 0.0
          limit = n - lag
          limit.times { |i| sum += centered[i] * centered[i + lag] }
          value = (sum / autocorrelation_zero).abs
          correlations[lag] = value
          if value > best_strength
            best_strength = value
            best_lag = lag
          end
        end
        local = (best_lag - 12).clamp(lower_lag, upper_lag - 1)..(best_lag + 12).clamp(lower_lag, upper_lag - 1)
        local_values = local.map { |lag| correlations.fetch(lag, 0.0) }
        confidence = best_strength / (local_values.sum / [local_values.length, 1].max + 1e-9) - 1.0
        bpm = 60.0 * fps / best_lag
        bpm *= 2 while bpm < 70
        bpm /= 2 while bpm > 180
        [bpm, confidence.clamp(0.0, 1.0)]
      end

      def beat_phase(env, bpm)
        fps = 1.0 / FRAME_SECONDS
        lag = 60.0 / bpm * fps
        best_phase = 0.0
        best_score = -1.0
        64.times do |step|
          phase = step * lag / 64.0
          index = phase
          values = []
          while index < env.length - 1
            values << env[index.to_i]
            index += lag
          end
          next if values.length < 4

          score = values.sum / values.length.to_f
          if score > best_score
            best_score = score
            best_phase = phase
          end
        end
        best_phase * FRAME_SECONDS
      end

      def grid_features(onsets, _env, bpm, phase)
        beat_seconds = 60.0 / bpm
        sixteenth_seconds = beat_seconds / 4.0
        bar_seconds = beat_seconds * 4.0
        if onsets.empty?
          return { "onset_density_per_bar" => 0.0, "offbeat_onset_share" => 0.5,
                   "timing_spread_ms" => 0.0, "swing_ratio" => 0.5 }
        end

        onset_times = onsets.map { |frame| frame * FRAME_SECONDS }
        nearest = onset_times.map { |time| ((time - phase) / sixteenth_seconds).round }
        deviations = onset_times.each_with_index.map do |time, index|
          ((time - phase) / sixteenth_seconds - nearest[index]) * sixteenth_seconds * 1_000.0
        end
        odd = nearest.each_index.select { |index| nearest[index].odd? }
        offbeat_share = odd.length / onset_times.length.to_f
        spread_values = deviations.each_with_index.filter_map do |value, index|
          value if onset_times[index] > phase + beat_seconds
        end
        spread = standard_deviation(spread_values).clamp(0.0, 120.0)
        swing = odd.empty? ? 0.5 : 0.5 + (median(odd.map { |index| deviations[index] }) / (sixteenth_seconds * 1_000.0)).clamp(0.0, 0.2)
        bars = [((onset_times.max - phase) / bar_seconds), 1.0].max
        { "onset_density_per_bar" => onset_times.length / bars,
          "offbeat_onset_share" => offbeat_share,
          "timing_spread_ms" => spread,
          "swing_ratio" => swing.clamp(0.5, 0.7) }
      end

      def standard_deviation(values)
        return 0.0 if values.empty?

        mean = values.sum / values.length.to_f
        Math.sqrt(values.sum { |value| (value - mean)**2 } / values.length.to_f)
      end

      def median(values)
        return 0.0 if values.empty?

        ordered = values.sort
        middle = ordered.length / 2
        ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
      end

      def chroma_of(power_spectrum, frequencies)
        chroma = Array.new(12, 0.0)
        resolution = frequencies[1] - frequencies[0]
        12.times do |pitch_class|
          energy = 0.0
          [1, 2, 3, 4].each do |harmonic|
            frequency = 65.406 * (2.0**(pitch_class / 12.0)) * harmonic
            next if frequency * (2.0**(0.5 / 12.0)) >= frequencies[-1]

            low = (frequency / (2.0**(0.5 / 12.0)) / resolution).to_i
            high = (frequency * (2.0**(0.5 / 12.0)) / resolution).to_i
            if high > low && low < power_spectrum.length
              power_spectrum[low...[high, power_spectrum.length].min].each { |value| energy += value }
            end
          end
          chroma[pitch_class] = energy
        end
        total = chroma.sum
        total.positive? ? chroma.map { |value| value / total } : chroma
      end

      def estimate_key(chroma)
        candidates = []
        12.times do |rotation|
          rotated = 12.times.map { |index| chroma[(index + rotation) % 12] }
          [["maj", KRUM_MAJOR], ["min", KRUM_MINOR]].each do |name, profile|
            candidates << [correlation(rotated, profile), rotation, name]
          end
        end
        candidates.sort_by! { |score, rotation, name| [-score, rotation, name] }
        score, rotation, name = candidates.first
        if candidates.length > 1
          other_score, other_rotation, other_name = candidates[1]
          if other_rotation == (rotation + 9) % 12 && name != other_name && (score - other_score).abs < 0.05
            flat_third = chroma[(rotation + 3) % 12]
            natural_third = chroma[(rotation + 4) % 12]
            name = "min" if name == "maj" && flat_third > natural_third * 1.02
            name = "maj" if name == "min" && natural_third > flat_third * 1.02
          end
        end
        label = "#{FLAT_BIAS.include?(rotation) ? PC_FLAT[rotation] : PC_SHARP[rotation]} #{name}"
        [label, score]
      end

      def correlation(left, right)
        left_mean = left.sum / left.length.to_f
        right_mean = right.sum / right.length.to_f
        numerator = denominator_left = denominator_right = 0.0
        left.each_index do |index|
          a = left[index] - left_mean
          b = right[index] - right_mean
          numerator += a * b
          denominator_left += a * a
          denominator_right += b * b
        end
        denominator = Math.sqrt(denominator_left * denominator_right)
        denominator.positive? ? numerator / denominator : 0.0
      end

      def chord_templates
        @chord_templates ||= begin
          templates = {}
          12.times do |root|
            CHORD_QUALITIES.each do |quality, intervals|
              vector = Array.new(12, 0.0)
              intervals.each { |interval| vector[(root + interval) % 12] = 1.0 }
              norm = Math.sqrt(vector.sum { |value| value * value })
              label = "#{FLAT_BIAS.include?(root) ? PC_FLAT[root] : PC_SHARP[root]}#{quality}"
              templates[label] = vector.map { |value| value / norm }
            end
          end
          templates
        end
      end

      def chord_changes(chroma_frames, frames_per_second)
        width = [(frames_per_second * 2).to_i | 1, 3].max
        smooth = 12.times.map do |pitch_class|
          median_filter(chroma_frames.map { |frame| frame[pitch_class] }, width)
        end
        unit = chroma_frames.each_index.map do |frame|
          vector = 12.times.map { |pitch_class| smooth[pitch_class][frame] }
          norm = Math.sqrt(vector.sum { |value| value * value }) + 1e-9
          vector.map { |value| value / norm }
        end
        novelty = (1...unit.length).map do |index|
          1.0 - 12.times.sum { |pc| unit[index][pc] * unit[index - 1][pc] }
        end
        maximum = novelty.max || 0.0
        return { "chord_changes" => 0, "chords" => [] } unless maximum.positive?

        threshold = [median(novelty) + 1.5 * standard_deviation(novelty), maximum * 0.45].max
        peaks = find_peaks(novelty, height: threshold, distance: [(frames_per_second * 1.5).to_i, 1].max)
        bounds = [0, *(peaks.map { |index| index + 1 }), chroma_frames.length]
        chords = bounds.each_cons(2).filter_map do |start_index, end_index|
          next unless end_index > start_index

          segment = Array.new(12) do |pc|
            rows = chroma_frames[start_index...end_index]
            rows.sum { |frame| frame[pc] } / rows.length.to_f
          end
          norm = Math.sqrt(segment.sum { |value| value * value }) + 1e-9
          segment.map! { |value| value / norm }
          label, = chord_templates.max_by { |_name, template| segment.each_index.sum { |pc| segment[pc] * template[pc] } }
          { "t" => round(start_index * 22 * FRAME_SECONDS, 2), "label" => label }
        end
        { "chord_changes" => peaks.length, "chords" => chords }
      end

      def melody_summary(spectra, frequencies, bpm)
        indices = indices_for(frequencies, 150, 1_400)
        return { "median_hz" => nil, "range_semitones" => nil, "note_density_per_bar" => nil } if indices.empty?

        frame_energy = spectra.map { |frame| indices.sum { |index| frame[index] } }
        gate = percentile(frame_energy, 55)
        voiced = frame_energy.each_index.select { |index| frame_energy[index] > gate }
        peak_bins = spectra.map { |frame| indices.max_by { |index| frame[index] } }
        fundamental_frequencies = voiced.map { |index| frequencies[peak_bins[index]] }.sort
        return { "median_hz" => nil, "range_semitones" => nil, "note_density_per_bar" => nil } if fundamental_frequencies.length < 8

        middle = median(fundamental_frequencies)
        low = percentile(fundamental_frequencies, 10)
        high = percentile(fundamental_frequencies, 90)
        range = 12.0 * Math.log2([high, 1e-6].max / [low, 1e-6].max)
        runs = 1
        voiced.each_cons(2) { |left, right| runs += 1 if (peak_bins[right] - peak_bins[left]).abs > 2 }
        bar_seconds = 60.0 / bpm * 4.0
        density = runs / [spectra.length * FRAME_SECONDS / bar_seconds, 1.0].max
        { "median_hz" => round(middle, 1), "range_semitones" => round(range, 1),
          "note_density_per_bar" => round(density, 2) }
      end

      def drum_grids(spectra, frequencies, drums_spectra, bpm, phase)
        grids = {}
        { "kick" => [30, 150], "snare" => [150, 700], "hat" => [5_000, 12_000] }.each do |name, band|
          source = drums_spectra || spectra
          indices = indices_for(frequencies, band[0], band[1])
          onsets = pick_onsets(spectral_flux(source, indices)).first
          if onsets.empty?
            grids[name] = Array.new(16, 0.0)
            next
          end

          sixteenth_seconds = (60.0 / bpm) / 4.0
          steps = onsets.map { |frame| (((frame * FRAME_SECONDS - phase) / sixteenth_seconds).round) % 16 }
          histogram = Array.new(16, 0)
          steps.each { |step| histogram[step] += 1 }
          maximum = histogram.max.to_f
          grids[name] = histogram.map { |value| maximum.positive? ? round(value / maximum, 3) : 0.0 }
        end
        grids
      end

      def energy_shares(stems_dir, max_duration)
        names = { "drums" => "drums_energy_share", "bass" => "bass_energy_share",
                  "other" => "other_energy_share", "vocals" => "vocal_energy_share" }
        powers = {}
        names.each do |stem, key|
          path = File.join(stems_dir, "#{stem}.wav")
          next unless File.file?(path)

          samples = read_wav(path, max_duration: max_duration)
          powers[key] = samples.sum { |value| value * value } / [samples.length, 1].max.to_f
        end
        return nil if powers.empty?
        total = powers.values.sum
        return nil unless total.positive?

        shares = powers.transform_values { |value| round(value / total, 3) }
        shares["other_energy_share"] = round(shares.fetch("other_energy_share", 0.0) + shares.fetch("vocal_energy_share", 0.0) * 0.5, 3)
        shares
      end

      def band_shares_from_mix(spectra, frequencies)
        power = mean_power_spectrum(spectra)
        share = lambda do |low, high|
          power.each_index.sum { |index| frequencies[index].between?(low, high) ? power[index] : 0.0 }
        end
        drums = share.call(30, 160) + share.call(4_500, 14_000) * 0.6 + share.call(150, 700) * 0.25
        bass = share.call(30, 220) * 0.7
        total = power.sum + 1e-12
        other = total - drums - bass
        { "drums_energy_share" => round([drums, 0.0].max / total, 3),
          "bass_energy_share" => round([bass, 0.0].max / total, 3),
          "other_energy_share" => round([other, 0.0].max / total, 3),
          "vocal_energy_share" => 0.0 }
      end

      def sections_of(samples, bpm)
        window = SAMPLE_RATE
        count = samples.length / window
        return [] if count < 4

        energies = Array.new(count) do |index|
          slice = samples[index * window, window]
          slice.sum { |value| value * value } / window.to_f
        end
        high = percentile(energies, 80)
        low = percentile(energies, 30)
        span = (60.0 / bpm) * 8.0
        duration = samples.length / SAMPLE_RATE.to_f
        sections = []
        time = 0.0
        while time < duration
          energy = energies[[(time.to_i), count - 1].min]
          level = energy > high ? "high" : (energy < low ? "low" : "mid")
          sections << { "start" => round(time, 1), "level" => level }
          time += span
        end
        sections
      end

      def clean_numbers(value)
        case value
        when Hash then value.transform_values { |item| clean_numbers(item) }
        when Array then value.map { |item| clean_numbers(item) }
        when Float then value.finite? ? value : nil
        else value
        end
      end

      def sort_hashes(value)
        case value
        when Hash
          value.keys.sort.each_with_object({}) { |key, result| result[key] = sort_hashes(value[key]) }
        when Array then value.map { |item| sort_hashes(item) }
        else value
        end
      end

      def round(value, places)
        factor = 10.0**places
        (value.to_f * factor).round / factor
      end

      def write_atomic(path, content)
        destination = File.expand_path(path)
        directory = File.dirname(destination)
        FileUtils.mkdir_p(directory)
        temporary = File.join(directory, ".#{File.basename(destination)}.#{Process.pid}.tmp")
        File.binwrite(temporary, content)
        File.rename(temporary, destination)
        destination
      ensure
        File.delete(temporary) if temporary && File.exist?(temporary)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  parser = OptionParser.new do |options|
    options.banner = "usage: ruby reference_analyzer.rb MIX.wav --json FEATURES.json [--stems DIR] [--max-duration SECONDS]"
    options.on("--json PATH", "Destination for the measured feature JSON") { |value| @json_path = value }
    options.on("--stems DIR", "Optional separated stem directory") { |value| @stems_dir = value }
    options.on("--max-duration SECONDS", Float, "Analyze only the first N seconds") { |value| @max_duration = value }
  end
  begin
    parser.parse!(ARGV)
    mix = ARGV.shift or raise Studio::DillaReference::AnalysisError, "a WAV input is required"
    raise Studio::DillaReference::AnalysisError, "--json PATH is required" if @json_path.to_s.empty?
    features = Studio::DillaReference::Analyzer.new.write(mix, @json_path, stems_dir: @stems_dir, max_duration: @max_duration)
    puts "analyzer: #{mix} -> #{@json_path} (#{features.fetch("bpm")} BPM, #{features.dig("harmony", "key")})"
  rescue OptionParser::ParseError, Studio::DillaReference::AnalysisError, SystemCallError, IOError => error
    warn "analyzer: #{error.class}: #{error.message}"
    exit 2
  end
end
