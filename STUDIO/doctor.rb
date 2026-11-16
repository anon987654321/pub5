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
      lora/consent.rb lora/consent.example.yml lora/validate.rb
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
      output, error, status = Subprocess.capture3(
        "git", "-C", @repository_root, "ls-files", "-z",
        timeout: 10
      )
      unless status.success?
        add(checks, "private_subject_history", "INCONCLUSIVE",
            "Git index could not be inspected; #{error.to_s.lines.last.to_s.strip}")
        return
      end

      offenders = output.split("\0").grep(PRIVATE_SUBJECT_PATH)
      if offenders.empty?
        add(checks, "private_subject_history", "PASS",
            "No subject-private data paths are tracked in the current Git index")
      else
        add(checks, "private_subject_history", "BLOCKED",
            "#{offenders.length} subject-private path(s) are tracked; rights and reachable Git history need operator review")
      end
    rescue StandardError => error
      add(checks, "private_subject_history", "INCONCLUSIVE",
          "Git index could not be inspected: #{error.class}: #{error.message}")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit Studio::Doctor.run(ARGV)
end
