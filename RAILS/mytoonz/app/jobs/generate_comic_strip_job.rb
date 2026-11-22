# frozen_string_literal: true

class GenerateComicStripJob < ApplicationJob
  queue_as :default

  def perform(comic_strip_id)
    comic_strip = ComicStrip.find(comic_strip_id)
    unless comic_strip.provider_consent_at.present?
      comic_strip.update!(status: "failed")
      Rails.logger.warn("Comic strip #{comic_strip.id} was not sent: provider consent is missing")
      return
    end

    result = ReplicateService.new.generate_comic_strip(
      prompt: comic_strip.prompt,
      style: comic_strip.style
    )

    prediction_id = result["id"].to_s
    if prediction_id.match?(ReplicateService::PREDICTION_ID)
      comic_strip.update!(status: "processing", prediction_id:)
      PollComicStripJob.set(wait: PollComicStripJob::POLL_INTERVAL).perform_later(comic_strip.id)
    else
      comic_strip.update!(status: "failed")
      Rails.logger.warn("GenerateComicStripJob failed for #{comic_strip.id}: provider returned no prediction ID")
    end
  rescue StandardError => error
    comic_strip&.update!(status: "failed")
    Rails.logger.error("GenerateComicStripJob failed for #{comic_strip_id}: #{error.class}")
  end
end
