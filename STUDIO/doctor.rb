#!/usr/bin/env ruby
# frozen_string_literal: true

# A read-only local readiness report. This deliberately does not render,
# upload, train, fetch model schemas, change consent, or rewrite Git history.

require "json"
require "optparse"
require "rubygems/version"
require_relative "output_paths"
require_relative "subprocess"
require_relative "lora/validate"

module Studio
  class Doctor
    MINIMUM_RUBY = Gem::Version.new("3.3.0").freeze

    REQUIRED_FILES = %w[
      Rakefile bin/studio doctor.rb
      dilla/dilla.rb dilla/lib/reference_analyzer.rb
      postpro/postpro.rb postpro/video.yml
      lora/consent.rb lora/consent.example.yml lora/validate.rb lora/migrate_local.rb
      lora/photograph.rb lora/idea_picture.rb lora/selfie_series.rb
      lora/selfies_gallery.rb replicate/client.rb replicate/models.yml
      rg69.html rg69.css rg69.js selfies.html selfies.css selfies.js
      vendor/swiper/swiper-bundle.min.js vendor/swiper/swiper-bundle.min.css
      vendor/tone/Tone.min.js
    ].freeze

    OPTIONAL_EXECUTABLES = %w[ffmpeg ffprobe node zip yt-dlp fluidsynth].freeze

    PRIVATE_SUBJECT_PATH = %r{
      \ASTUDIO/lora/[^/]+/
      (?:
        (?:sources|references|evidence|weights|out|retouched|dataset(?:_[^/]*)?)(?:/|\z)
        |
        (?:consent\.yml|subject\.env|ledger\.jsonl)\z
      )
    }x.freeze
    PRIVATE_SUBJECT_MEDIA_PATH = %r{\ASTUDIO/lora/[^/]+/[^/]+\.(?:jpg|jpeg|png|webp|gif|mp4|mov|webm|wav|mp3|zip|safetensors|ckpt|pt|pth)\z}i
    PRIVATE_RENDER_PATH = %r{\ASTUDIO/lora/[^/]+_(?:selfie|film)_}
    PRIVATE_POSTPRO_SOURCE = %r{\ASTUDIO/postpro/IMG_}
    PRIVATE_LEGACY_SUBJECT_PATH = %r{\ASTUDIO/replicate/lora/.*/(?:sources|dataset|weights|out)(?:/|\z)}
    PRIVATE_MEDIA_EXTENSIONS = %w[jpg jpeg png webp gif mp4 mov webm wav mp3 zip safetensors ckpt pt pth].freeze
    PRIVATE_MEDIA_PATHSPECS = PRIVATE_MEDIA_EXTENSIONS.map { |extension| ":(glob)STUDIO/lora/**/*.#{extension}" }.freeze

    PRIVATE_PATHSPECS = %w[
      :(glob)STUDIO/lora/*/sources/**
      :(glob)STUDIO/lora/*/references/**
      :(glob)STUDIO/lora/*/evidence/**
      :(glob)STUDIO/lora/*/weights/**
      :(glob)STUDIO/lora/*/out/**
      :(glob)STUDIO/lora/*/retouched/**
      :(glob)STUDIO/lora/*/dataset/**
      :(glob)STUDIO/lora/*/dataset_*/**
      :(glob)STUDIO/lora/*/consent.yml
      :(glob)STUDIO/lora/*/subject.env
      :(glob)STUDIO/lora/*/ledger.jsonl
      :(glob)STUDIO/lora/*_selfie_*
      :(glob)STUDIO/lora/*_film_*
      :(glob)STUDIO/postpro/IMG_*
      :(glob)STUDIO/replicate/lora/**/sources/**
      :(glob)STUDIO/replicate/lora/**/dataset/**
      :(glob)STUDIO/replicate/lora/**/weights/**
      :(glob)STUDIO/replicate/lora/**/out/**
    ].concat(PRIVATE_MEDIA_PATHSPECS).freeze

    def self.ruby_supported?(version)
      Gem::Version.new(version.to_s) >= MINIMUM_RUBY
    rescue ArgumentError
      false
    end

    def self.ready?(checks)
      checks.none? { |check| %w[FAIL BLOCKED INCONCLUSIVE].include?(check.fetch("state")) }
    end

    def initialize(root: File.expand_path(__dir__), ruby_version: RUBY_VERSION)
      @root = File.expand_path(root)
      @repository_root = File.expand_path("..", @root)
      @ruby_version = ruby_version.to_s
    end

    def report
      checks = []
      add(checks, "ruby", self.class.ruby_supported?(@ruby_version) ? "PASS" : "FAIL",
          "Ruby #{@ruby_version}; minimum supported version is #{MINIMUM_RUBY}")

      missing = REQUIRED_FILES.reject { |path| File.file?(File.join(@root, path)) }
      add(checks, "entrypoints", missing.empty? ? "PASS" : "FAIL",
          missing.empty? ? "#{REQUIRED_FILES.length} required files are present" :
            "Missing required files: #{missing.join(', ')}")

      begin
        render_path = OutputPaths.render_directory
        safe = render_path.start_with?(File::SEPARATOR) && !OutputPaths.inside_repository?(render_path)
        add(checks, "output_path", safe ? "PASS" : "FAIL",
            safe ? "Render directory is absolute and outside the checkout" :
              "Render directory must be absolute and outside the checkout")
      rescue StandardError => error
        add(checks, "output_path", "FAIL", "#{error.class}: #{error.message}")
      end

      begin
        profile_report = Lora::Validator.new(root: File.join(@root, "lora")).validate_all
        invalid = profile_report.fetch("subjects").count { |subject| subject.fetch("state") != "PASS" }
        not_training_ready = profile_report.fetch("subjects").count { |subject| !subject.fetch("training_ready") }
        state = invalid.zero? ? "PASS" : "FAIL"
        detail = "#{profile_report.fetch('subject_count')} profile(s) inspected; " \
                 "#{invalid} structural failure(s); #{not_training_ready} not approved for training"
        add(checks, "lora_profiles", state, detail)
      rescue StandardError => error
        add(checks, "lora_profiles", "FAIL", "#{error.class}: #{error.message}")
      end

      private_media_check(checks)

      OPTIONAL_EXECUTABLES.each do |name|
        available = Subprocess.on_path?(name)
        add(checks, "executable:#{name}", available ? "AVAILABLE" : "OPTIONAL_MISSING",
            available ? "#{name} is on PATH" : "#{name} is optional and not on PATH")
      end

      {
        "schema" => "studio.doctor.v1",
        "read_only" => true,
        "provider_calls" => 0,
        "ready" => self.class.ready?(checks),
        "checks" => checks
      }
    end

    def self.run(argv)
      options = { json: false }
      OptionParser.new do |parser|
        parser.banner = "usage: bin/studio doctor [--json]"
        parser.on("--json", "print the machine-readable readiness report") { options[:json] = true }
      end.parse!(argv)

      report = new.report
      if options[:json]
        puts JSON.pretty_generate(report)
      else
        puts "STUDIO doctor — #{report.fetch('ready') ? 'READY' : 'BLOCKED'}"
        report.fetch("checks").each do |check|
          puts format("%-17s %-15s %s", check.fetch("state"), check.fetch("id"), check.fetch("detail"))
        end
        puts "provider_calls: 0 (read-only)"
      end
      report.fetch("ready") ? 0 : 2
    rescue OptionParser::ParseError => error
      warn "studio doctor: #{error.message}"
      64
    end

    private

    def add(checks, id, state, detail)
      checks << { "id" => id, "state" => state, "detail" => detail }
    end

    def private_media_check(checks)
      index_output, index_error, index_status = Subprocess.capture3(
        "git", "-C", @repository_root, "ls-files", "-z",
        timeout: 10
      )
      if index_status.success?
        indexed = index_output.split("\0").count { |path| private_path?(path) }
        add(checks, "private_subject_index", indexed.zero? ? "PASS" : "BLOCKED",
            indexed.zero? ? "No subject-private paths are tracked in the current index" :
              "#{indexed} subject-private path(s) are tracked in the current index")
      else
        add(checks, "private_subject_index", "INCONCLUSIVE",
            "Git index could not be inspected; #{index_error.to_s.lines.last.to_s.strip}")
      end

      shallow_output, shallow_error, shallow_status = Subprocess.capture3(
        "git", "-C", @repository_root, "rev-parse", "--is-shallow-repository",
        timeout: 10
      )
      unless shallow_status.success? && shallow_output.strip == "false"
        detail = if shallow_status.success? && shallow_output.strip == "true"
                   "Local repository is shallow; reachable Git history is incomplete"
                 else
                   "Shallow-repository status could not be verified; #{shallow_error.to_s.lines.last.to_s.strip}"
                 end
        add(checks, "private_subject_history", "INCONCLUSIVE", detail)
        return
      end

      history_output, history_error, history_status = Subprocess.capture3(
        "git", "-C", @repository_root, "log", "--all", "--format=", "--name-only", "--",
        *PRIVATE_PATHSPECS,
        timeout: 45
      )
      if history_status.success?
        historical = history_output.lines.map(&:strip).reject(&:empty?).uniq
        add(checks, "private_subject_history", historical.empty? ? "PASS" : "BLOCKED",
            historical.empty? ?
              "No subject-private paths found in reachable local branches or tags; other clones and remote mirrors are not assessed" :
              "#{historical.length} subject-private path(s) remain in reachable local Git history; other clones and remote mirrors are not assessed")
      else
        add(checks, "private_subject_history", "INCONCLUSIVE",
            "Reachable local Git history could not be inspected; #{history_error.to_s.lines.last.to_s.strip}")
      end
    rescue StandardError => error
      add(checks, "private_subject_history", "INCONCLUSIVE",
          "Private-media history could not be inspected: #{error.class}: #{error.message}")
    end

    def private_path?(path)
      path.match?(PRIVATE_SUBJECT_PATH) ||
        path.match?(PRIVATE_SUBJECT_MEDIA_PATH) ||
        path.match?(PRIVATE_RENDER_PATH) ||
        path.match?(PRIVATE_POSTPRO_SOURCE) ||
        path.match?(PRIVATE_LEGACY_SUBJECT_PATH)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Studio::Doctor.run(ARGV)
end
