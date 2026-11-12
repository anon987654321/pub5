#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "photograph/idea_picture"
require_relative "photograph/selfie_series"

if $PROGRAM_NAME == __FILE__
  options = { film: false, duration: 5, subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild") }
  OptionParser.new do |parser|
    parser.on("--film", "also render the short film") { options[:film] = true }
    parser.on("--animate SOURCE", "animate an existing LoRA still into a short clip") { |value| options[:animate] = value }
    parser.on("--prompt TEXT", "motion direction for --animate") { |value| options[:prompt] = value }
    parser.on("--duration N", Integer, "film duration in seconds (1..10)") { |value| options[:duration] = value }
    parser.on("--subject NAME", "subject directory under STUDIO/lora") { |value| options[:subject] = value }
    parser.on("--selfie-series", "render a bounded selfie series for --subject") { options[:series] = true }
    parser.on("--count N", Integer, "series length, 1..24") { |value| options[:count] = value }
    parser.on("--replace", "delete only this subject's previous generated stills before rendering") { options[:replace] = true }
    parser.on("--check-model", "verify the subject's local manifest or private Replicate model") { options[:check_model] = true }
  end.parse!

  result = begin
    if options[:check_model]
      abort "--replace is not valid with --check-model" if options[:replace]
      { "subject" => options[:subject], "model" => Studio::Visual::IdeaPicture.new(subject: options[:subject]).validate_model! }
    elsif options[:series]
      Studio::Visual::SelfieSeries.new(subject: options[:subject]).run(
        count: options[:count] || 12,
        replace: options[:replace] == true,
      )
    elsif options[:animate]
      prompt = options[:prompt].to_s.strip
      abort "usage: ruby STUDIO/photograph.rb --animate SOURCE --subject NAME --prompt 'MOTION' [--duration 5]" if prompt.empty?
      abort "--replace is only valid with --selfie-series" if options[:replace]

      Studio::Visual::IdeaPicture.new(subject: options[:subject]).animate(
        options[:animate], prompt, duration: options[:duration]
      )
    else
      abort "--replace is only valid with --selfie-series" if options[:replace]
      prompt = ARGV.join(" ").strip
      abort "usage: ruby STUDIO/photograph.rb [--subject NAME] [--film] PROMPT" if prompt.empty?

      Studio::Visual::IdeaPicture.new(subject: options[:subject]).write(
        prompt, film: options[:film], duration: options[:duration]
      )
    end
  rescue Studio::Lora::Consent::Error => error
    warn "BLOCKED: #{error.message}"
    exit 2
  end
  puts JSON.generate(result)
end
