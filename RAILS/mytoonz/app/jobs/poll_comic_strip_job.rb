# frozen_string_literal: true

class PollComicStripJob < ApplicationJob
  queue_as :default

  POLL_INTERVAL = 8.seconds
  MAX_ATTEMPTS = 40

  def perform(comic_strip_id, attempt: 0)
    comic_strip = ComicStrip.find_by(id: comic_strip_id)
    return unless comic_strip&.status == "processing"

    unless comic_strip.provider_consent_at.present?
      comic_strip.update!(status: "failed")
      return
    end

    if attempt >= MAX_ATTEMPTS
      comic_strip.update!(status: "failed")
      Rails.logger.warn("Comic strip #{comic_strip.id} timed out while waiting for Replicate")
      return
    end

    result = ReplicateService.new.get_prediction(comic_strip.prediction_id)
    case result["status"]
    when "succeeded"
      urls = Array(result["output"]).select { |url| ReplicateService.safe_output_url?(url) }
      comic_strip.update!(status: urls.empty? ? "failed" : "completed", image_urls: urls)
    when "failed", "canceled"
      comic_strip.update!(status: "failed")
    when "starting", "processing", "queued"
      self.class.set(wait: POLL_INTERVAL).perform_later(comic_strip.id, attempt: attempt + 1)
    else
      comic_strip.update!(status: "failed")
      Rails.logger.warn("Replicate returned an unknown state for comic strip #{comic_strip.id}")
    end
  rescue StandardError => error
    comic_strip&.update!(status: "failed") if comic_strip&.status == "processing"
    Rails.logger.warn("PollComicStripJob failed for #{comic_strip_id}: #{error.class}")
  end
end
