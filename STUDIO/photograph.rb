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
    parser.on("--subject NAME", "subject directory under STUDIO/lora (default ragnhild)") { |value| options[:subject] = value }
    parser.on("--selfie-series", "render a bounded selfie series for --subject") { options[:series] = true }
    parser.on("--count N", Integer, "series length, 1..24 (default 10)") { |value| options[:count] = value }
    parser.on("--keep", "keep this subject's earlier generated stills instead of replacing them") { options[:keep] = true }
    parser.on("--engine NAME", "render with a reference model from STUDIO/replicate/models.yml") { |value| options[:engine] = value }
    parser.on("--models", "list the Replicate engines and exit") { options[:models] = true }
    parser.on("--check-model", "verify the subject's local manifest or private Replicate model") { options[:check_model] = true }
  end.parse!

  result = begin
    if options[:models]
      Studio::ReplicateClient::Models.engines.each do |name, spec|
        puts format("%-38s %-9s %s", name, spec["likeness"], Array(spec["inputs"]).join(", "))
      end
      exit 0
    elsif options[:check_model]
      { "subject" => options[:subject], "model" => Studio::Visual::IdeaPicture.new(subject: options[:subject]).validate_model! }
    elsif options[:series]
      # Sensible defaults, no flags required: ten sittings for the default
      # subject, graded heavy, replacing that subject's earlier stills so the
      # folder is the current series. --keep preserves the previous run instead.
      # --engine NAME swaps the trained LoRA for a reference model that keeps the
      # face from the subject's own photographs in lora/<subject>/references.
      Studio::ReplicateClient::Models.engine(options[:engine]) if options[:engine]
      Studio::Visual::SelfieSeries.new(subject: options[:subject], engine: options[:engine]).run(
        count: options[:count] || 10,
        replace: options[:keep] != true,
      )
    elsif options[:animate]
      prompt = options[:prompt].to_s.strip
      abort "usage: ruby STUDIO/photograph.rb --animate SOURCE --subject NAME --prompt 'MOTION' [--duration 5]" if prompt.empty?

      Studio::Visual::IdeaPicture.new(subject: options[:subject]).animate(
        options[:animate], prompt, duration: options[:duration]
      )
    else
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
