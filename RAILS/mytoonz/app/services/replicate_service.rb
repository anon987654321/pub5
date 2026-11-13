# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class ReplicateService
  API_BASE = URI("https://api.replicate.com/v1/").freeze
  MODEL_VERSION = "db21e45d3f7023abc2a46ee38a23973f6dce16bb082a930b0c49861f96d1e5bf"
  MAX_RESPONSE_BYTES = 256_000
  PREDICTION_ID = /\A[a-zA-Z0-9_-]{1,128}\z/
  OUTPUT_HOST = /\A(?:[a-z0-9-]+\.)*replicate\.delivery\z/i

  def self.safe_output_url?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(OUTPUT_HOST)
  rescue URI::InvalidURIError
    false
  end

  def initialize(api_token: ENV["REPLICATE_API_TOKEN"])
    @api_token = api_token.to_s.strip
  end

  def generate_comic_strip(prompt:, style: "comic")
    return failure("REPLICATE_API_TOKEN not set") if @api_token.empty?

    text = prompt.to_s.strip
    return failure("Prompt is required") if text.empty?
    return failure("Prompt is too long") if text.length > 4_000

    request(
      :post,
      "predictions",
      payload: {
        version: MODEL_VERSION,
        input: {
          prompt: enhanced_prompt(text, style),
          negative_prompt: "blurry, bad quality, distorted, ugly",
          width: 1024,
          height: 576,
          num_outputs: 4
        }
      }
    )
  end

  def get_prediction(prediction_id)
    return failure("REPLICATE_API_TOKEN not set") if @api_token.empty?

    id = prediction_id.to_s
    return failure("Invalid prediction ID") unless PREDICTION_ID.match?(id)

    request(:get, "predictions/#{id}")
  end

  private

  def request(method, path, payload: nil)
    uri = URI.join(API_BASE.to_s, path)
    headers = {
      "Authorization" => "Bearer #{@api_token}",
      "Accept" => "application/json"
    }
    body = nil
    if payload
      headers["Content-Type"] = "application/json"
      body = JSON.generate(payload)
    end

    response = Shared::OutboundHttp.request(
      uri,
      method: method,
      headers: headers,
      body: body,
      max_body: MAX_RESPONSE_BYTES,
      open_timeout: 5,
      read_timeout: 20
    )

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("Replicate returned HTTP #{response.code}")
      return failure("Replicate HTTP #{response.code}")
    end

    parsed = JSON.parse(response.body.to_s)
    parsed.is_a?(Hash) ? parsed : failure("Replicate returned an unexpected response")
  rescue JSON::ParserError
    failure("Replicate returned invalid JSON")
  rescue StandardError => error
    Rails.logger.warn("Replicate request failed: #{error.class}")
    failure("Replicate request failed")
  end

  def enhanced_prompt(user_prompt, style)
    modifiers = {
      "comic" => "comic book style, vibrant colors, bold lines",
      "anime" => "anime art style, manga",
      "cartoon" => "cartoon style, colorful, fun",
      "noir" => "noir comic art, dramatic monochrome lighting",
      "manga" => "manga illustration, expressive ink work",
      "retro" => "retro comic illustration, halftone print texture"
    }
    modifier = modifiers.fetch(style.to_s, modifiers.fetch("comic"))
    "#{modifier}, #{user_prompt}, high quality, detailed"
  end

  def failure(message)
    { "error" => message }
  end
end
