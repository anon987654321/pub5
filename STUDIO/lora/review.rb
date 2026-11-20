#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "time"
require "vips"
require_relative "idea_picture"
require_relative "consent"
require_relative "../postpro/uncanny"

module Studio
  module Lora
    module Review
      SUBJECTS = %w[johann ragnhild merethe].freeze
      IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze
      RENDER_COUNT = 6
      TILE_WIDTH = 420
      TILE_HEIGHT = 560
      COLUMNS = 3
      BACKGROUND = [18, 18, 18].freeze

      class Error < StandardError; end

      class Builder
        def initialize(subject:, root: IdeaPicture::SUBJECTS)
          @subject = subject.to_s
          raise ArgumentError, "unknown subject" unless SUBJECTS.include?(@subject)

          @root = File.expand_path(root)
          @subject_directory = File.join(@root, @subject)
          raise Error, "subject directory is missing or symlinked" unless
            File.directory?(@subject_directory) && !File.symlink?(@subject_directory)
        end

        def render_files
          patterns = IMAGE_EXTENSIONS.map do |extension|
            File.join(@root, "postpro_#{@subject}_selfie_*.#{extension}")
          end
          files = patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.sort
          files.select do |path|
            stat = File.lstat(path)
            stat.file? && !stat.symlink? && stat.uid == Process.uid &&
              stat.nlink == 1 && (stat.mode & 0o077).zero? && stat.size.positive?
          rescue SystemCallError
            false
          end
        end

        def reference_files
          dataset = File.join(@subject_directory, "dataset")
          raise Error, "private training dataset is missing; no approved comparison images available" unless
            File.directory?(dataset) && !File.symlink?(dataset)
          stat = File.lstat(dataset)
          raise Error, "training dataset must be owner-only (0700)" unless
            stat.uid == Process.uid && (stat.mode & 0o077).zero?

          images = Dir.children(dataset).sort.filter_map do |name|
            next unless IMAGE_EXTENSIONS.include?(File.extname(name).downcase)

            path = File.join(dataset, name)
            file_stat = File.lstat(path)
            next unless file_stat.file? && !file_stat.symlink? && file_stat.uid == Process.uid &&
                        file_stat.nlink == 1 && (file_stat.mode & 0o077).zero? && file_stat.size.positive?

            path
          rescue SystemCallError
            nil
          end
          raise Error, "fewer than three approved training photographs are available for comparison" if images.length < 3

          indices = [0, images.length / 2, images.length - 1].uniq
          indices.map { |index| images.fetch(index) }
        end

        def build
          consent = Consent.require!(
            subject: @subject, subject_directory: @subject_directory, action: :generation
          )
          renders = render_files
          unless renders.length == RENDER_COUNT
            raise Error, "expected #{RENDER_COUNT} final, private Postpro renders for #{@subject}; found #{renders.length}"
          end
          references = reference_files
          picture = Studio::Visual::IdeaPicture.new(subject: @subject, subjects_root: @root)
          version = picture.send(:still_model)

          cache = File.join(@subject_directory, ".cache")
          secure_directory!(cache)
          reviews = File.join(cache, "reviews")
          secure_directory!(reviews)
          stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S")
          output = File.join(reviews, stamp)
          secure_directory!(output)

          sheet_path = File.join(output, "contact-sheet.jpg")
          write_contact_sheet(references, renders, sheet_path)
          metrics = renders.map do |path|
            reading = Postpro::Uncanny.read(path)
            {
              "file" => File.basename(path),
              "texture" => reading.texture,
              "specular_spread" => reading.specular_spread,
              "clipping_percent" => reading.clipping,
              "tonal_range" => reading.tonal_range,
            }
          end

          report = {
            "schema" => "studio.lora.review.v1",
            "subject" => @subject,
            "model_version" => version,
            "render_count" => renders.length,
            "reference_count" => references.length,
            "contact_sheet" => File.basename(sheet_path),
            "measurements" => metrics,
            "identity_assessment" => "NOT_AUTOMATED",
            "human_review_required" => true,
            "approval_field" => "LIKELINESS_REVIEWED_VERSION",
            "approval_instruction" => "Compare every full-size render with the approved source photographs. Do not approve a model from the contact sheet or image-quality metrics alone.",
            "provider_calls" => 0,
            "consent_valid" => consent.fetch("valid"),
          }
          write_private(File.join(output, "review.json"), JSON.pretty_generate(report) + "\n")
          write_private(File.join(output, "index.html"), html_document(report))
          {
            "subject" => @subject,
            "status" => "AWAITING_HUMAN_IDENTITY_REVIEW",
            "contact_sheet" => sheet_path,
            "review_report" => File.join(output, "review.json"),
            "html" => File.join(output, "index.html"),
            "model_version" => version,
            "render_count" => renders.length,
            "reference_count" => references.length,
            "provider_calls" => 0,
          }
        end

        private

        def write_contact_sheet(references, renders, path)
          entries = references.map.with_index { |file, index| [file, "REFERENCE #{index + 1}"] } +
                    renders.map.with_index { |file, index| [file, format("RENDER %02d", index + 1)] }
          cells = entries.map { |file, label| contact_cell(file, label) }
          sheet = Vips::Image.arrayjoin(
            cells, across: COLUMNS, shim: 10, background: BACKGROUND, valign: :low
          )
          sheet.write_to_file(path, Q: 92)
          File.chmod(0o600, path)
        end

        def contact_cell(path, label)
          tile = Vips::Image.thumbnail(path, TILE_WIDTH, height: TILE_HEIGHT)
          caption = Vips::Image.text(label, dpi: 96, font: "sans 16")
          strip = caption.embed(12, 8, tile.width, caption.height + 16)
          tile.join(strip, :vertical, expand: true, background: BACKGROUND)
        rescue Vips::Error => error
          raise Error, "cannot build contact sheet for #{File.basename(path)}: #{error.message}"
        end

        def html_document(report)
          rows = report.fetch("measurements").map do |row|
            "<tr><td>#{escape_html(row.fetch("file"))}</td>" \
              "<td>#{format("%.4f", row.fetch("texture"))}</td>" \
              "<td>#{format_optional(row["specular_spread"])}</td>" \
              "<td>#{format("%.4f", row.fetch("clipping_percent"))}%</td>" \
              "<td>#{format("%.4f", row.fetch("tonal_range"))}</td></tr>"
          end.join("\n")
          <<~HTML
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Private LoRA review — #{escape_html(@subject)}</title>
              <style>
                :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
                body { max-width: 1180px; margin: 36px auto; padding: 0 24px; color: #171717; }
                img { display: block; width: 100%; height: auto; border: 1px solid #bbb; }
                table { width: 100%; border-collapse: collapse; margin: 24px 0; }
                th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
                .warning { font-weight: 600; }
                code { overflow-wrap: anywhere; }
              </style>
            </head>
            <body>
              <h1>Private likeness review — #{escape_html(@subject)}</h1>
              <p>Candidate model: <code>#{escape_html(report.fetch("model_version"))}</code></p>
              <p class="warning">Identity verdict: NOT AUTOMATED. Compare all six full-size renders with the references. Do not approve from image metrics alone.</p>
              <img src="contact-sheet.jpg" alt="Three approved source images and six generated final portraits">
              <h2>Postpro measurements</h2>
              <p>Whole-frame texture, specular spread, clipping and tonal range are diagnostic proxies, not face recognition.</p>
              <table>
                <thead><tr><th>File</th><th>Texture</th><th>Specular spread</th><th>Clipping</th><th>Tonal range</th></tr></thead>
                <tbody>#{rows}</tbody>
              </table>
              <p>After visual review, record the exact immutable version in the owner's private <code>subject.env</code> as <code>LIKELINESS_REVIEWED_VERSION</code>. Leave it unset if any portrait does not clearly match.</p>
            </body>
            </html>
          HTML
        end

        def format_optional(value)
          value.nil? ? "n/a" : format("%.4f", value)
        end

        def escape_html(value)
          value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
        end

        def secure_directory!(path)
          raise Error, "refusing symlink directory: #{path}" if File.symlink?(path)

          FileUtils.mkdir_p(path, mode: 0o700)
          stat = File.lstat(path)
          raise Error, "review directory is not owned by the current user" unless stat.directory? && stat.uid == Process.uid
          File.chmod(0o700, path)
        end

        def write_private(path, contents)
          raise Error, "review file already exists: #{File.basename(path)}" if File.exist?(path) || File.symlink?(path)

          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            file.write(contents)
            file.flush
            file.fsync
          end
          File.chmod(0o600, path)
        end
      end

      module_function

      def run_cli(argv)
        options = { subject: nil }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/review.rb --subject NAME"
          parser.on("--subject NAME", "review the six latest final stills for one subject") { |value| options[:subject] = value }
        end.parse!(argv)
        raise ArgumentError, "--subject is required" if options[:subject].to_s.empty?

        result = Builder.new(subject: options[:subject]).build
        puts JSON.pretty_generate(result)
        0
      rescue Error, Consent::Error, ArgumentError, SystemCallError, IOError, Vips::Error => error
        warn "BLOCKED: #{error.class}: #{error.message}"
        2
      end
    end
  end
end

exit Studio::Lora::Review.run_cli(ARGV) if $PROGRAM_NAME == __FILE__
