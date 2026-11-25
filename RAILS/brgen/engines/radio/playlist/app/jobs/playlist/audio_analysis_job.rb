# frozen_string_literal: true

require "json"
require "shared/subprocess"

class Playlist::AudioAnalysisJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "playlist-audio-analysis", duration: 5.minutes

  BINS = 96
  SAMPLE_RATE = 8_000
  MAX_DURATION = 7_200
  FORMATS = "mp3,wav,flac,ogg,mov,mp4,m4a,3gp,3g2,mj2,matroska,webm,aac,aiff"
  CACHE_KEY = "playlist_waveform_v1"

  def perform(blob_id)
    return unless %w[ffmpeg ffprobe].all? { |command| Shared::Subprocess.on_path?(command) }

    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob && blob.byte_size <= Shared::AttachmentLimits::KINDS.fetch(:audio).fetch(:max_bytes)
    return if blob.metadata.key?(CACHE_KEY) && blob.metadata.key?("playlist_duration_seconds")

    attachments = ActiveStorage::Attachment.where(record_type: "Playlist::Track", name: "audio_file", blob_id: blob_id)
    return unless attachments.exists?

    result = blob.open { |file| self.class.analyze(file.path) }
    return unless result

    blob.with_lock do
      blob.update!(metadata: blob.metadata.merge(CACHE_KEY => result.fetch(:peaks), "playlist_duration_seconds" => result.fetch(:duration).round))
    end

    # Only current references to this blob receive its measured metadata.
    tracks = Playlist::Track.where(id: attachments.select(:record_id))
    tracks.update_all(duration_seconds: result.fetch(:duration).round, updated_at: Time.current)
    result.fetch(:tags).each do |field, value|
      tracks.where(field => [nil, ""]).update_all(field => value)
    end
  rescue Shared::Subprocess::TimeoutError, JSON::ParserError, ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError => error
    Rails.logger.warn("playlist audio analysis unavailable for blob #{blob_id}: #{error.class}")
  end

  # Probe and decode local bytes only; playlists/remote input formats are not
  # accepted. astats emits one actual peak per bounded sample window.
  def self.analyze(path)
    input = ["-protocol_whitelist", "file,pipe", "-format_whitelist", FORMATS]
    probe, _, status = Shared::Subprocess.capture3(
      "ffprobe", "-v", "error", *input, "-show_entries", "format=duration:format_tags=title,artist,album,genre",
      "-of", "json", "-i", path, timeout: 15
    )
    return unless status.success?

    format = JSON.parse(probe).fetch("format", {})
    duration = Float(format["duration"], exception: false)
    return unless duration&.finite? && duration.positive? && duration <= MAX_DURATION

    samples = [(duration * SAMPLE_RATE / BINS).ceil, 1].max
    filter = "aresample=#{SAMPLE_RATE},asetnsamples=n=#{samples}:p=0,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.Peak_level:file=-"
    output, _, status = Shared::Subprocess.capture3(
      "ffmpeg", "-nostdin", "-v", "error", "-xerror", *input, "-threads", "1", "-t", MAX_DURATION.to_s,
      "-i", path, "-map", "0:a:0", "-vn", "-sn", "-dn", "-filter_threads", "1",
      "-af", filter, "-frames:a", BINS.to_s, "-f", "null", "-", timeout: 120
    )
    return unless status.success?

    peaks = output.lines.filter_map do |line|
      next unless line.start_with?("lavfi.astats.Overall.Peak_level=")

      value = line.split("=", 2).last.strip
      next 0.0 if value == "-inf"

      db = Float(value, exception: false)
      (10 ** (db / 20)).clamp(0, 1).round(4) if db&.finite?
    end.first(BINS)
    return if peaks.empty?

    source_tags = format.fetch("tags", {}).transform_keys(&:downcase)
    tags = %w[artist album genre].filter_map do |key|
      value = source_tags[key].to_s.strip.first(80)
      [key, value] if value.present?
    end.to_h
    { duration: duration, peaks: peaks, tags: tags }
  end
end
