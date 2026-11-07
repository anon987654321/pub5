#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "photograph/idea_picture"
require_relative "photograph/reference_picture"
require_relative "photograph/selfie_series"

if $PROGRAM_NAME == __FILE__
  options = {
    film: false,
    duration: 5,
    subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild"),
    reference: false,
    reference_images: [],
    reference_roles: [],
    look: "natural_selfie",
    seed: 42,
    cost_limit_usd: nil,
    selfie_series: false,
    output_directory: File.expand_path("~/ideas")
  }
  OptionParser.new do |parser|
    parser.on("--film", "also render the short film (trained-LoRA route only)") { options[:film] = true }
    parser.on("--reference", "use consent-gated reference-conditioned generation") { options[:reference] = true }
    parser.on("--reference-image PATH", "local image under the subject's private sources/ directory; repeat 1-3 times") { |value| options[:reference_images] << value }
    parser.on("--reference-role ROLE", "role for each image: front, three_quarter, expression, or other; repeat in image order") { |value| options[:reference_roles] << value }
    parser.on("--look NAME", "lookbook profile for the reference route") { |value| options[:look] = value }
    parser.on("--seed N", Integer, "reproducible image seed") { |value| options[:seed] = value }
    parser.on("--cost-limit-usd AMOUNT", Float, "maximum estimated cost accepted for this one-image request") { |value| options[:cost_limit_usd] = value }
    parser.on("--duration N", Integer, "film duration in seconds") { |value| options[:duration] = value }
    parser.on("--selfie-series", "refresh old verified renders and create ten varied selfies per local LoRA model") { options[:selfie_series] = true }
    parser.on("--output-dir DIR", "private local output root for --selfie-series") { |value| options[:output_directory] = File.expand_path(value) }
    parser.on("--subject NAME", "subject directory under STUDIO/replicate/lora") { |value| options[:subject] = value }
  end.parse!

  if options[:selfie_series]
    abort "--selfie-series does not accept an additional prompt" unless ARGV.empty?
    abort "--selfie-series cannot be combined with --film or --reference" if options[:film] || options[:reference] || options[:reference_images].any?
    begin
      result = Studio::Visual::SelfieSeries.new(output_directory: options[:output_directory]).write
    rescue StandardError => error
      abort "selfie-series blocked: #{error.class}: #{error.message}"
    end
    puts JSON.generate(result)
    exit(result.fetch("status") == "complete" ? 0 : 1)
  end

  prompt = ARGV.join(" ").strip
  abort "usage: ruby STUDIO/photograph.rb [--film | --reference --reference-image PATH] PROMPT" if prompt.empty?
  abort "--film cannot be combined with --reference" if options[:film] && options[:reference]

  if options[:reference]
    abort "--reference-image is required (repeat 1-3 times)" if options[:reference_images].empty?
    abort "--cost-limit-usd is required; current one-image estimate is USD 0.03" unless options[:cost_limit_usd]

    result = Studio::Visual::ReferencePicture.new(subject: options[:subject]).write(
      prompt:,
      references: options[:reference_images],
      reference_roles: options[:reference_roles].empty? ? nil : options[:reference_roles],
      look: options[:look],
      seed: options[:seed],
      cost_limit_usd: options[:cost_limit_usd]
    )
  else
    result = Studio::Visual::IdeaPicture.new(subject: options[:subject]).write(
      prompt, film: options[:film], duration: options[:duration]
    )
  end
  puts JSON.generate(result)
end
