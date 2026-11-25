#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../replicate/api"
require_relative "../replicate/interactive"
require_relative "idea_picture"
require_relative "selfie_series"

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

      Studio::Visual::IdeaPicture.new(
        subject: request.fetch("subject", "ragnhild"), engine: request["engine"],
        film_engine: request["film_engine"], film_resolution: request["film_resolution"],
        inference_profile: request["inference_profile"]
      ).write(
        prompt, film: request.fetch("film", false), duration: request.fetch("duration", 5)
      )
    end,
    "series" => lambda do |request|
      subject = request.fetch("subject", "ragnhild")
      paths = Studio::Visual::SelfieSeries.new(
        subject:, engine: request["engine"], inference_profile: request["inference_profile"]
      ).run(
        count: request.fetch("count", 4)
      )
      { "subject" => subject, "rendered" => paths, "prior_renders_retained" => true }
    end,
    "animate" => lambda do |request|
      source = request["source"].to_s
      prompt = request["prompt"].to_s
      raise ArgumentError, "animate needs a source and a prompt" if source.empty? || prompt.empty?

      picture = Studio::Visual::IdeaPicture.new(
        subject: request.fetch("subject", "ragnhild"), film_engine: request["film_engine"],
        film_resolution: request["film_resolution"]
      )
      result = picture.animate(source, prompt, duration: request.fetch("duration", 5))
      soundtrack = request["soundtrack"].to_s
      result["scored"] = picture.add_soundtrack(result["clip"], soundtrack) unless soundtrack.empty?
      result
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

# The film-engine question, shared by the animate wizard branch. The default is
# MiniMax H3 Highspeed; H3 Lite and the rest of the image_to_video catalogue
# remain selectable.
def studio_film_engine_choice(wizard)
  catalogue = Studio::ReplicateClient::Models.film_engines
  default = Studio::Visual::IdeaPicture::FILM
  options = catalogue.map do |name, spec|
    ["#{name}#{name == default ? ' (default)' : ''}", name]
  end
  wizard.choose("Which film engine?", options, default: default)
end

def studio_photograph_options(argv)
  options = {
    film: false, duration: 5, count: 4, all_subjects: false, inference_profile: nil,
    subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild")
  }
  OptionParser.new do |parser|
    parser.on("--film", "also render the short film") { options[:film] = true }
    parser.on("--animate SOURCE", "animate an existing LoRA still into a short clip") { |value| options[:animate] = value }
    parser.on("--prompt TEXT", "motion direction for --animate") { |value| options[:prompt] = value }
    parser.on("--duration N", Integer, "film duration in seconds (1..10)") { |value| options[:duration] = value }
    parser.on("--soundtrack PATH", "lay a music bed under the film (e.g. dilla.wav)") { |value| options[:soundtrack] = value }
    parser.on("--subject NAME", "subject directory under STUDIO/lora (default ragnhild)") { |value| options[:subject] = value }
    parser.on("--selfie-series", "render portraits using the subject's references when present, otherwise the pinned LoRA") { options[:series] = true }
    parser.on("--all-subjects", "preflight each subject and render those with valid consent and references or a pinned LoRA") { options[:all_subjects] = true }
    parser.on("--count N", Integer, "series length, 1..24 (default 4)") { |value| options[:count] = value }
    # Compatibility flag; earlier stills are always retained.
    parser.on("--keep", "compatibility flag; prior generated stills are always retained") { options[:keep] = true }
    parser.on("--engine NAME", "render with a model from STUDIO/replicate/models.yml") { |value| options[:engine] = value }
    parser.on("--inference-profile NAME", "LoRA profile from training_standards.yml (identity, balanced, detail, draft)") { |value| options[:inference_profile] = value }
    parser.on("--film-engine NAME", "animate with a model from image_to_video (default minimax/h3-highspeed)") { |value| options[:film_engine] = value }
    parser.on("--film-resolution RES", "H3 Lite resolution: 480P (default) or 768P") { |value| options[:film_resolution] = value }
    parser.on("--free", "stay inside Replicate's free tier (flux-dev, flux-schnell)") { options[:engine] = "black-forest-labs/flux-dev" }
    parser.on("--models", "list the Replicate engines and exit") { options[:models] = true }
    parser.on("--check-model", "verify the subject's local manifest or private Replicate model") { options[:check_model] = true }
  end.parse!(argv)
  options
end

# All-subject generation is independent per person. Every subject is preflighted
# before the first prediction, but one person's missing permission/model must not
# prevent another subject with a complete, valid preflight from proceeding.
def studio_all_subjects_render(subjects:, count:, inference_profile: nil, series_factory: nil)
  factory = series_factory || ->(subject) { Studio::Visual::SelfieSeries.new(subject:, inference_profile:) }
  prepared = subjects.map do |subject|
    begin
      series = factory.call(subject)
      series.preflight!
      { "subject" => subject, "state" => "READY", "series" => series }
    rescue StandardError => error
      { "subject" => subject, "state" => "BLOCKED",
        "reason" => "#{error.class}: #{error.message.to_s.gsub(/\s+/, " ")[0, 240]}" }
    end
  end

  rendered = {}
  subject_status = {}
  prepared.each do |entry|
    subject = entry.fetch("subject")
    if entry.fetch("state") == "BLOCKED"
      rendered[subject] = []
      subject_status[subject] = { "state" => "BLOCKED", "reason" => entry.fetch("reason") }
      next
    end

    begin
      paths = entry.fetch("series").run(count:)
      rendered[subject] = paths
      complete = paths.length == count
      subject_status[subject] = {
        "state" => complete ? "RENDERED" : "INCOMPLETE",
        "expected" => count,
        "rendered" => paths.length,
      }
    rescue StandardError => error
      rendered[subject] = []
      subject_status[subject] = {
        "state" => "FAILED",
        "reason" => "#{error.class}: #{error.message.to_s.gsub(/\s+/, " ")[0, 240]}",
      }
    end
  end

  statuses = subject_status.values
  all_complete = !statuses.empty? && statuses.all? { |item| item.fetch("state") == "RENDERED" }
  any_output = rendered.values.any?(&:any?)
  {
    "status" => all_complete ? "COMPLETE" : (any_output ? "PARTIAL" : "BLOCKED"),
    "subjects" => rendered,
    "subject_status" => subject_status,
    "prior_renders_retained" => true,
  }
end

def studio_photograph_interactive?(arguments, tty:)
  arguments.empty? && tty
end

if $PROGRAM_NAME == __FILE__
  if Studio::Api.requested?(ARGV)
    exit Studio::Api.respond(studio_photograph_actions, argv: ARGV)
  end

  wizard = Studio::Interactive.new
  interactive = studio_photograph_interactive?(ARGV, tty: wizard.tty?)
  # Capture the original invocation mode before OptionParser consumes flags.
  options = studio_photograph_options(ARGV)

  if interactive
    mode = wizard.choose("What shall STUDIO photograph?", [
      ["A selfie series", :series],
      ["One picture", :picture],
      ["A short film from an existing still", :animate],
    ])
    options[:subject] = wizard.ask("Subject", default: options[:subject])
    case mode
    when :series
      options[:series] = true
      options[:count] = wizard.number("How many sittings", default: 4, range: 1..24)
      # The ordinary selfie path is always this subject's trained LoRA.
      puts "Earlier portraits are always retained."
    when :picture
      options[:prompt] = wizard.ask("Describe the picture")
      options[:engine] = studio_engine_choice(wizard)
      options[:film] = wizard.confirm("Also render the short film?", default: false)
    when :animate
      options[:animate] = wizard.ask("Path to the still to animate")
      options[:prompt] = wizard.ask("Motion direction")
      options[:duration] = wizard.number("Duration in seconds", default: 5, range: 1..10)
      options[:film_engine] = studio_film_engine_choice(wizard)
    end
  end

  if options[:film_engine]
    Studio::ReplicateClient::Models.film_engine(options[:film_engine])
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
      { "subject" => options[:subject], "model" => Studio::Visual::IdeaPicture.new(subject: options[:subject], lora_only: true).validate_model! }
    elsif options[:all_subjects]
      raise ArgumentError, "--all-subjects requires the subject's trained LoRA; --engine is not allowed" if options[:engine]

      studio_all_subjects_render(
        subjects: %w[johann ragnhild merethe], count: options[:count] || 4,
        inference_profile: options[:inference_profile]
      )
    elsif options[:series]
      # A series uses the subject's references and the catalogue default
      # reference engine when present; without references it uses the pinned
      # LoRA. An explicit --engine is an override, not a required choice.
      Studio::ReplicateClient::Models.engine(options[:engine]) if options[:engine]
      Studio::Visual::SelfieSeries.new(
        subject: options[:subject], engine: options[:engine], inference_profile: options[:inference_profile]
      ).run(
        count: options[:count] || 4
      )
    elsif options[:animate]
      prompt = options[:prompt].to_s.strip
      abort "usage: ruby STUDIO/lora/photograph.rb --animate SOURCE --subject NAME --prompt 'MOTION' [--duration 5] [--soundtrack dilla.wav]" if prompt.empty?

      picture = Studio::Visual::IdeaPicture.new(
        subject: options[:subject], film_engine: options[:film_engine],
        film_resolution: options[:film_resolution], inference_profile: options[:inference_profile]
      )
      result = picture.animate(options[:animate], prompt, duration: options[:duration])
      result["scored"] = picture.add_soundtrack(result["clip"], options[:soundtrack]) if options[:soundtrack]
      result
    else
      prompt = ARGV.join(" ").strip
      abort "usage: ruby STUDIO/lora/photograph.rb [--subject NAME] [--film] PROMPT" if prompt.empty?

      Studio::Visual::IdeaPicture.new(
        subject: options[:subject], film_engine: options[:film_engine],
        film_resolution: options[:film_resolution], inference_profile: options[:inference_profile]
      ).write(
        prompt, film: options[:film], duration: options[:duration]
      )
    end
  end
  puts JSON.generate(result)
  exit 1 if options[:all_subjects] && result["status"] == "PARTIAL"
  exit 2 if options[:all_subjects] && result["status"] == "BLOCKED"
end
