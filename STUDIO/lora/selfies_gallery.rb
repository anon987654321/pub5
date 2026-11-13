#!/usr/bin/env ruby
# frozen_string_literal: true

# selfies_gallery — build the manifest the selfies page reads.
#
# The gallery (STUDIO/lora/selfies.html) shows a subject's stills and films over
# the dilla bed. The renders live in STUDIO/lora/ and are not tracked; this tool
# scans them and writes STUDIO/lora/selfies-manifest.js, the one generated file
# the page needs, so the page stays static and the media stays private and out
# of git. The page, its manifest and the renders share a directory, so every
# media path in the manifest is written relative to that directory.
#
#   ruby STUDIO/lora/selfies_gallery.rb
#   ruby STUDIO/lora/selfies_gallery.rb --subject ragnhild --soundtrack selfies-dilla.mp3
#   ruby STUDIO/lora/selfies_gallery.rb api '{"action":"build"}'
#
# It reads only; it never renders, uploads or deletes. A film is a still that
# has an animation beside it: the animate step writes <stem>.mp4 and, when a
# soundtrack is laid under it, <stem>_audio.mp4. The scored cut is preferred.

require "json"
require "optparse"
require "fileutils"
require "pathname"
require_relative "../api"

module Studio
  module Visual
    class SelfiesGallery
      ROOT = File.expand_path("..", __dir__).freeze
      LORA = File.join(ROOT, "lora").freeze
      DEFAULT_OUT = File.join(LORA, "selfies-manifest.js").freeze
      DEFAULT_SOUNDTRACK = "selfies-dilla.mp3".freeze

      STILL_EXTENSIONS = %w[jpg jpeg png webp].freeze
      FILM_EXTENSIONS = %w[mp4 webm mov].freeze
      # A render's stem: <subject>_selfie_NN or <subject>_film_STAMP. postpro
      # prefixes its graded still, so the leading token is what names the subject.
      SUBJECT = /\A(?:(?:postpro_)?(?<subject>[a-zA-Z0-9_-]+?))_(?:selfie|film)_/i.freeze

      def initialize(root: LORA, out: DEFAULT_OUT, subject: nil, soundtrack: DEFAULT_SOUNDTRACK)
        @root = File.expand_path(root)
        @out = File.expand_path(out)
        @subject = subject&.to_s
        @soundtrack = soundtrack&.to_s
      end

      def build
        raise ArgumentError, "lora directory is not readable: #{@root}" unless File.directory?(@root)

        stills = files(STILL_EXTENSIONS)
        films = files(FILM_EXTENSIONS)
        scored = films.select { |path| File.basename(path, ".*").end_with?("_audio") }

        items = []
        stills.each do |path|
          subject = subject_of(path) or next
          next if @subject && subject != @subject

          clip = film_for(path, films, scored)
          items << {
            "kind" => "still",
            "subject" => subject,
            "src" => relative(path),
            "caption" => caption(subject, path)
          }
          if clip
            items << {
              "kind" => "film",
              "subject" => subject,
              "src" => relative(clip),
              "poster" => relative(path),
              "caption" => "#{caption(subject, path)} (film)"
            }
          end
        end

        # A film with no still beside it still belongs in the gallery. The
        # scored cut is checked first so it is the one listed when both exist.
        (scored + films).uniq.each do |path|
          next if items.any? { |item| item["src"] == relative(path) }

          subject = subject_of(path) or next
          next if @subject && subject != @subject

          items << {
            "kind" => "film",
            "subject" => subject,
            "src" => relative(path),
            "caption" => "#{subject} film"
          }
        end

        manifest = {
          "generated_by" => "STUDIO/lora/selfies_gallery.rb",
          "subjects" => items.map { |item| item["subject"] }.uniq.sort,
          "count" => items.count { |item| item["kind"] == "still" },
          "soundtrack" => soundtrack_path,
          "items" => items
        }
        write(manifest)
        manifest
      end

      private

      def files(extensions)
        Dir[File.join(@root, "**", "*")].select do |path|
          File.file?(path) && !File.symlink?(path) &&
            extensions.include?(File.extname(path).delete_prefix(".").downcase)
        end.sort
      end

      def subject_of(path)
        match = SUBJECT.match(File.basename(path))
        match && match[:subject]
      end

      # The animation of a still shares its stem; the scored cut wins over the
      # silent original when both exist.
      def film_for(still, films, scored)
        stem = File.basename(still, ".*")
        directory = File.dirname(still)
        candidates = scored + films
        candidates.find do |path|
          File.dirname(path) == directory && File.basename(path, ".*").start_with?(stem)
        end
      end

      def caption(subject, path)
        index = File.basename(path)[/_selfie_(\d+)/, 1]
        index ? "#{subject} selfie #{index}" : "#{subject} still"
      end

      def relative(path)
        Pathname.new(path).relative_path_from(Pathname.new(File.dirname(@out))).to_s
      end

      # Only record a soundtrack that exists; a missing bed is not an error, the
      # page simply omits the control. The path is read relative to the manifest
      # (the page directory) and written back the same way.
      def soundtrack_path
        return nil if @soundtrack.nil? || @soundtrack.empty?

        candidate = File.expand_path(@soundtrack, File.dirname(@out))
        File.file?(candidate) ? relative(candidate) : @soundtrack
      end

      def write(manifest)
        FileUtils.mkdir_p(File.dirname(@out))
        body = "// Generated by STUDIO/lora/selfies_gallery.rb — do not edit.\n" \
               "window.STUDIO_SELFIES = #{JSON.pretty_generate(manifest)};\n"
        File.write(@out, body)
      end
    end

    # The CLI: build the manifest, optionally scoped to one subject.
    module SelfiesGalleryCLI
      module_function

      def run(argv)
        if Studio::Api.requested?(argv)
          return Studio::Api.respond(actions, argv:)
        end

        options = { subject: nil, out: SelfiesGallery::DEFAULT_OUT, soundtrack: SelfiesGallery::DEFAULT_SOUNDTRACK }
        OptionParser.new do |parser|
          parser.banner = "usage: ruby STUDIO/lora/selfies_gallery.rb [options]"
          parser.on("--subject NAME", "limit to one subject") { |value| options[:subject] = value }
          parser.on("--out PATH", "manifest path") { |value| options[:out] = value }
          parser.on("--soundtrack PATH", "recorded bed, relative to the manifest directory") { |value| options[:soundtrack] = value }
        end.parse!(argv)

        manifest = SelfiesGallery.new(out: options[:out], subject: options[:subject],
                                      soundtrack: options[:soundtrack]).build
        puts JSON.generate(manifest)
      end

      def actions
        {
          "build" => lambda do |request|
            SelfiesGallery.new(
              out: request.fetch("out", SelfiesGallery::DEFAULT_OUT),
              subject: request["subject"],
              soundtrack: request.fetch("soundtrack", SelfiesGallery::DEFAULT_SOUNDTRACK)
            ).build
          end
        }
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  Studio::Visual::SelfiesGalleryCLI.run(ARGV)
end
