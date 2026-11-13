#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "api"
require_relative "interactive"
require_relative "photograph/idea_picture"
require_relative "photograph/selfie_series"

# The API actions MASTER reaches over the subprocess boundary. Same classes the
# CLI uses, no prompt, one JSON response.
def studio_photograph_actions
  {
    "engines" => lambda do |_request|
      default = Studio::ReplicateClient::Models.default_engine
      Studio::ReplicateClient::Models.engines.map do |name, spec|
        { "name" => name, "likeness" => spec["likeness"], "free" => !!spec["free"],
          "default" => name == default, "inputs" => Array(spec["inputs"]) }
      end
    end,
    "render" => lambda do |request|
      prompt = request["prompt"].to_s
      raise ArgumentError, "render needs a prompt" if prompt.empty?

      Studio::Visual::IdeaPicture.new(subject: request.fetch("subject", "ragnhild"), engine: request["engine"]).write(
        prompt, film: request.fetch("film", false), duration: request.fetch("duration", 5)
      )
    end,
    "series" => lambda do |request|
      subject = request.fetch("subject", "ragnhild")
      paths = Studio::Visual::SelfieSeries.new(subject:, engine: request["engine"]).run(
        count: request.fetch("count", 10), replace: request.fetch("replace", true)
      )
      { "subject" => subject, "rendered" => paths }
    end,
    "animate" => lambda do |request|
      source = request["source"].to_s
      prompt = request["prompt"].to_s
      raise ArgumentError, "animate needs a source and a prompt" if source.empty? || prompt.empty?

      Studio::Visual::IdeaPicture.new(subject: request.fetch("subject", "ragnhild")).animate(
        source, prompt, duration: request.fetch("duration", 5)
      )
    end,
    "check_model" => lambda do |request|
      { "subject" => request.fetch("subject", "ragnhild"),
        "model" => Studio::Visual::IdeaPicture.new(subject: request.fetch("subject", "ragnhild")).validate_model! }
    end,
  }
end

# The engine question, shared by the wizard branches below. The catalogue is the
# source: each engine is labelled with how it reaches a likeness.
def studio_engine_choice(wizard)
  models = Studio::ReplicateClient::Models
  default = models.default_engine
  options = models.engines.map do |name, spec|
    marks = []
    marks << "default" if name == default
    marks << "free" if spec["free"]
    ["#{name} — #{spec['likeness']}#{marks.empty? ? '' : " (#{marks.join(', ')})"}", name]
  end
  wizard.choose("Which Replicate engine?", options, default: default)
end

if $PROGRAM_NAME == __FILE__
  if Studio::Api.requested?(ARGV)
    exit Studio::Api.respond(studio_photograph_actions, argv: ARGV)
  end

  options = { film: false, duration: 5, subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild") }
  wizard = Studio::Interactive.new
  # No arguments in a terminal: ask, rather than require a remembered flag.
  # Flags still work for scripts, and a piped run keeps its defaults.
  unless ARGV.empty? || !wizard.tty?
    OptionParser.new do |parser|
      parser.on("--film", "also render the short film") { options[:film] = true }
      parser.on("--animate SOURCE", "animate an existing LoRA still into a short clip") { |value| options[:animate] = value }
      parser.on("--prompt TEXT", "motion direction for --animate") { |value| options[:prompt] = value }
      parser.on("--duration N", Integer, "film duration in seconds (1..10)") { |value| options[:duration] = value }
      parser.on("--subject NAME", "subject directory under STUDIO/lora (default ragnhild)") { |value| options[:subject] = value }
      parser.on("--selfie-series", "render a bounded selfie series for --subject") { options[:series] = true }
      parser.on("--count N", Integer, "series length, 1..24 (default 10)") { |value| options[:count] = value }
      parser.on("--keep", "keep this subject's earlier generated stills instead of replacing them") { options[:keep] = true }
      parser.on("--engine NAME", "render with a model from STUDIO/replicate/models.yml") { |value| options[:engine] = value }
      parser.on("--free", "stay inside Replicate's free tier (flux-dev, flux-schnell)") { options[:engine] = "black-forest-labs/flux-dev" }
      parser.on("--models", "list the Replicate engines and exit") { options[:models] = true }
      parser.on("--check-model", "verify the subject's local manifest or private Replicate model") { options[:check_model] = true }
    end.parse!
  end

  if ARGV.empty? && wizard.tty?
    mode = wizard.choose("What shall STUDIO photograph?", [
      ["A selfie series", :series],
      ["One picture", :picture],
      ["A short film from an existing still", :animate],
    ])
    options[:subject] = wizard.ask("Subject", default: options[:subject])
    case mode
    when :series
      options[:series] = true
      options[:count] = wizard.number("How many sittings", default: 10, range: 1..24)
      options[:engine] = studio_engine_choice(wizard)
      options[:keep] = !wizard.confirm("Replace this subject's earlier stills?", default: true)
    when :picture
      options[:prompt] = wizard.ask("Describe the picture")
      options[:engine] = studio_engine_choice(wizard)
      options[:film] = wizard.confirm("Also render the short film?", default: false)
    when :animate
      options[:animate] = wizard.ask("Path to the still to animate")
      options[:prompt] = wizard.ask("Motion direction")
      options[:duration] = wizard.number("Duration in seconds", default: 5, range: 1..10)
    end
  end

  result = begin
    if options[:models]
      default = Studio::ReplicateClient::Models.default_engine
      Studio::ReplicateClient::Models.engines.each do |name, spec|
        marks = []
        marks << "default" if name == default
        marks << "free" if spec["free"]
        puts format("%-38s %-9s %-16s %s", name, spec["likeness"], marks.join(","), Array(spec["inputs"]).join(", "))
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
  end
  puts JSON.generate(result)
end
