#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require "vips"
require_relative "idea_picture"
require_relative "consent"
require_relative "validate"
require_relative "../postpro/uncanny"

module Studio
  module Lora
    module Review
      SUBJECTS = %w[johann ragnhild merethe].freeze
      IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze
      RENDER_COUNT = 4
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
          rows = ledger_rows
          latest = rows.reverse.find do |row|
            row["kind"] == "series_start" && row["subject"] == @subject
          end
          paths = if latest
                    rows.filter_map do |row|
                      next unless row["kind"] == "render" && row["series_id"] == latest["series_id"]

                      row["path"].to_s unless row["path"].to_s.empty?
                    end
                  else
                    legacy_render_files
                  end
          paths.map { |path| File.expand_path(path) }.uniq.select { |path| private_render?(path) }
        end

        def ledger_rows
          path = File.join(@subject_directory, "ledger.jsonl")
          return [] unless File.exist?(path) || File.symlink?(path)

          stat = File.lstat(path)
          unless stat.file? && !stat.symlink? && stat.uid == Process.uid &&
                 stat.nlink == 1 && (stat.mode & 0o077).zero?
            raise Error, "subject ledger must be an owner-only, singly-linked regular file"
          end

          File.readlines(path, chomp: true, encoding: "UTF-8").filter_map do |line|
            next if line.empty?

            row = JSON.parse(line)
            raise Error, "subject ledger row must be an object" unless row.is_a?(Hash)

            row
          end
        rescue JSON::ParserError, EncodingError => error
          raise Error, "subject ledger is not valid JSONL: #{error.message}"
        end

        def legacy_render_files
          patterns = IMAGE_EXTENSIONS.map do |extension|
            File.join(@root, "postpro_#{@subject}_selfie_*.#{extension}")
          end
          patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.sort
        end

        def private_render?(path)
          expanded = File.expand_path(path)
          return false unless expanded.start_with?("#{@root}#{File::SEPARATOR}")
          return false unless File.basename(expanded).start_with?("postpro_#{@subject}_selfie_")
          return false unless IMAGE_EXTENSIONS.include?(File.extname(expanded).delete_prefix(".").downcase)

          stat = File.lstat(expanded)
          stat.file? && !stat.symlink? && stat.uid == Process.uid &&
            stat.nlink == 1 && (stat.mode & 0o077).zero? && stat.size.positive?
        rescue SystemCallError
          false
        end

        def validate_render_count!(renders, expected: RENDER_COUNT)
          count = Array(renders).length
          return true if count == expected

          raise Error, "expected #{expected} private Postpro renders for #{@subject}; found #{count}"
        end

        def reference_files
          dataset = File.join(@subject_directory, "dataset")
          raise Error, "private training dataset is missing; no approved comparison images available" unless
            File.directory?(dataset) && !File.symlink?(dataset)
          stat = File.lstat(dataset)
          raise Error, "training dataset must be owner-only (0700)" unless
            stat.uid == Process.uid && (stat.mode & 0o077).zero?

          images = Dir.children(dataset).sort.filter_map do |name|
            # IMAGE_EXTENSIONS carries bare words; File.extname carries the dot.
            next unless IMAGE_EXTENSIONS.include?(File.extname(name).delete_prefix(".").downcase)

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

        def build(candidate: false)
          consent = Consent.require!(
            subject: @subject, subject_directory: @subject_directory, action: :training
          )
          cache = File.join(@subject_directory, ".cache")
          secure_directory!(cache)

          # Reuse the exact read-only gate used before paid training. A candidate
          # must not be generated from an incomplete, altered or unconsented set.
          require_training_ready!

          # Check the private reference set and pinned candidate before any
          # provider prediction. A bad dataset must not consume a paid sample.
          references = reference_files
          picture = Studio::Visual::IdeaPicture.new(subject: @subject, subjects_root: @root)
          version = picture.send(:still_model)

          render_kind = candidate ? "UNAPPROVED_CANDIDATE" : "FINAL_SERIES"
          if candidate
            output = new_review_directory(File.join(cache, "likeness-review"))
            renders = render_candidate_renders(output)
            validate_render_count!(renders, expected: 3)
          else
            renders = render_files
            validate_render_count!(renders)
            output = new_review_directory(File.join(cache, "reviews"))
          end
          sheet_path = File.join(output, "contact-sheet.jpg")
          write_contact_sheet(references, renders, sheet_path, render_label: candidate ? "CANDIDATE" : "RENDER")
          reference_metrics = measure_images(references)
          metrics = measure_images(renders)
          images = review_images(output, references, renders)

          report = {
            "schema" => "studio.lora.review.v1",
            "subject" => @subject,
            "model_version" => version,
            "render_kind" => render_kind,
            "render_count" => renders.length,
            "reference_count" => references.length,
            "contact_sheet" => File.basename(sheet_path),
            "reference_measurements" => reference_metrics,
            "measurements" => metrics,
            "images" => images,
            "identity_assessment" => "NOT_AUTOMATED",
            "human_review_required" => true,
            "approval_field" => "LIKELINESS_REVIEWED_VERSION",
            "approval_instruction" => "Compare every full-size render with the approved source photographs. Do not approve a model from the contact sheet or image-quality metrics alone.",
            "provider_predictions" => (candidate ? renders.length : 0),
            "provider_uploads" => 0,
            "consent_valid" => consent.fetch("valid"),
          }
          write_private(File.join(output, "review.json"), JSON.pretty_generate(report) + "\n")
          write_private(File.join(output, "index.html"), html_document(report))
          {
            "subject" => @subject,
            "status" => "AWAITING_HUMAN_IDENTITY_REVIEW",
            "render_kind" => render_kind,
            "contact_sheet" => sheet_path,
            "review_report" => File.join(output, "review.json"),
            "html" => File.join(output, "index.html"),
            "model_version" => version,
            "render_count" => renders.length,
            "reference_count" => references.length,
            "provider_predictions" => (candidate ? renders.length : 0),
            "provider_uploads" => 0,
          }
        end

        private

        def require_training_ready!
          report = Validator.new(root: @root).validate_subject(@subject)
          return report if report["training_ready"] == true

          details = Array(report["blockers"]).map { |item| item["detail"] || item["id"] }
          details.concat(Array(report["errors"]))
          raise Error, "subject validation blocks likeness review: #{details.join("; ")}"
        end

        def new_review_directory(parent)
          secure_directory!(parent)
          stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
          path = File.join(parent, stamp)
          secure_directory!(path)
          path
        end

        def render_candidate_renders(output)
          picture = Studio::Visual::IdeaPicture.new(
            subject: @subject, subjects_root: @root, directory: output,
            lora_only: true, allow_unreviewed_likeness: true
          )
          picture.validate_model!
          [1, 4, 6].each_with_index.map do |scene_number, index|
            picture.write(
              Studio::Lora::Selfie.scene(scene_number, subject: @subject),
              film: false,
              output_stem: "#{@subject}_candidate_#{format("%02d", index + 1)}",
              grade_seed: Studio::Lora::Selfie.grade_seed(scene_number, @subject)
            ).fetch("still")
          end
        end

        def measure_images(paths)
          paths.map do |path|
            reading = Postpro::Uncanny.read(path)
            {
              "file" => File.basename(path),
              "texture" => reading.texture,
              "specular_spread" => reading.specular_spread,
              "clipping_percent" => reading.clipping,
              "tonal_range" => reading.tonal_range,
            }
          end
        end

        def review_images(output, references, renders)
          entries = references.map { |path| ["REFERENCE", path] } + renders.map do |path|
            ["#{renders.length == 3 ? "CANDIDATE" : "FINAL"}", path]
          end
          entries.map do |role, path|
            stat = File.lstat(path)
            unless stat.file? && !stat.symlink? && stat.uid == Process.uid && stat.nlink == 1 &&
                   (stat.mode & 0o077).zero?
              raise Error, "review image is not a private, singly-linked file: #{File.basename(path)}"
            end

            {
              "role" => role,
              "file" => File.basename(path),
              "relative_path" => Pathname.new(path).relative_path_from(Pathname.new(output)).to_s,
            }
          end
        end

        def write_contact_sheet(references, renders, path, render_label: "RENDER")
          entries = references.map.with_index { |file, index| [file, "REFERENCE #{index + 1}"] } +
                    renders.map.with_index { |file, index| [file, format("%s %02d", render_label, index + 1)] }
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
          render_rows = measurement_rows(report.fetch("measurements"))
          reference_rows = measurement_rows(report.fetch("reference_measurements"))
          gallery = report.fetch("images").map do |entry|
            relative = escape_html(entry.fetch("relative_path"))
            label = escape_html(entry.fetch("role"))
            filename = escape_html(entry.fetch("file"))
            "<figure><a href=\"#{relative}\"><img src=\"#{relative}\" loading=\"lazy\" alt=\"#{label}: #{filename}\"></a>" \
              "<figcaption><strong>#{label}</strong><br>#{filename} · open full resolution</figcaption></figure>"
          end.join("\n")
          <<~HTML
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Private likeness review — #{escape_html(@subject)}</title>
              <style>
                :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
                body { max-width: 1320px; margin: 36px auto; padding: 0 24px; color: #171717; }
                img { display: block; width: 100%; height: auto; border: 1px solid #bbb; }
                table { width: 100%; border-collapse: collapse; margin: 16px 0 32px; font-variant-numeric: tabular-nums; }
                th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
                .warning { font-weight: 600; }
                code { overflow-wrap: anywhere; }
                .gallery { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 16px; margin: 24px 0 40px; }
                figure { margin: 0; }
                figure img { aspect-ratio: 4 / 5; object-fit: contain; background: #eee; }
                figcaption { padding-top: 8px; font-size: 13px; line-height: 1.45; overflow-wrap: anywhere; }
              </style>
            </head>
            <body>
              <h1>Private likeness review — #{escape_html(@subject)} — #{escape_html(report.fetch("render_kind"))}</h1>
              <p>Candidate model: <code>#{escape_html(report.fetch("model_version"))}</code></p>
              <p class="warning">Identity verdict: NOT AUTOMATED. Compare all #{Integer(report.fetch("render_count"))} full-size #{report.fetch("render_kind") == "UNAPPROVED_CANDIDATE" ? "candidate" : "final"} renders with the references. Do not approve from image metrics alone.</p>
              <img src="contact-sheet.jpg" alt="#{Integer(report.fetch("reference_count"))} approved source images and #{Integer(report.fetch("render_count"))} #{report.fetch("render_kind") == "UNAPPROVED_CANDIDATE" ? "candidate" : "final"} portraits">
              <h2>Full-resolution source and render files</h2>
              <div class="gallery">#{gallery}</div>
              <h2>Source reference measurements</h2>
              <p>Whole-frame texture, specular spread, clipping and tonal range are diagnostic proxies, not face recognition.</p>
              <table>
                <thead><tr><th>Reference</th><th>Texture</th><th>Specular spread</th><th>Clipping</th><th>Tonal range</th></tr></thead>
                <tbody>#{reference_rows}</tbody>
              </table>
              <h2>Generated image measurements</h2>
              <table>
                <thead><tr><th>File</th><th>Texture</th><th>Specular spread</th><th>Clipping</th><th>Tonal range</th></tr></thead>
                <tbody>#{render_rows}</tbody>
              </table>
              <p>After visual review, record the exact immutable version in the owner's private <code>subject.env</code> as <code>LIKELINESS_REVIEWED_VERSION</code>. Leave it unset if any portrait does not clearly match.</p>
            </body>
            </html>
          HTML
        end

        def measurement_rows(rows)
          rows.map do |row|
            "<tr><td>#{escape_html(row.fetch("file"))}</td>" \
              "<td>#{format("%.4f", row.fetch("texture"))}</td>" \
              "<td>#{format_optional(row["specular_spread"])}</td>" \
              "<td>#{format("%.4f", row.fetch("clipping_percent"))}%</td>" \
              "<td>#{format("%.4f", row.fetch("tonal_range"))}</td></tr>"
          end.join("\n")
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
        options = { subject: nil, candidate: false }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/review.rb --subject NAME"
          parser.on("--subject NAME", "review a subject's portraits") { |value| options[:subject] = value }
          parser.on("--candidate", "render three private LoRA samples before approving a new model") { options[:candidate] = true }
        end.parse!(argv)
        raise ArgumentError, "--subject is required" if options[:subject].to_s.empty?

        result = Builder.new(subject: options[:subject]).build(candidate: options[:candidate])
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
