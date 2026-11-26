#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"
require "vips"
require_relative "idea_picture"
require_relative "consent"
require_relative "validate"
require_relative "quality"
require_relative "../postpro/uncanny"
require_relative "../postpro/lib/quality_analyzer"

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
      QUALITY_RUBRIC = {
        "identity" => "Does the face remain recognisably the same person at full size?",
        "expression" => "Does the expression feel natural rather than performed?",
        "composition" => "Is there one clear visual centre, with deliberate framing and readable depth?",
        "lighting" => "Do light direction, shadow shape and catchlights agree?",
        "optical_realism" => "Do skin texture, highlights, eyes and fine detail read as photographic?",
        "colour_and_tone" => "Are skin tones, highlight roll-off and shadow detail convincing?",
        "technical_integrity" => "Are focus, edges, hands, teeth, jewellery and background details intact?",
        "originality" => "Does this frame convey a distinct intentional moment rather than a generic output?",
        "set_coherence" => "Does the frame contribute a materially different treatment while preserving the subject and the brief?",
      }.freeze

      class Error < StandardError; end

      def self.write_contact_sheet(references, renders, path, render_label: "RENDER")
        entries = references.map.with_index { |file, index| [file, "HOLDOUT #{index + 1}"] } +
                  renders.map.with_index { |file, index| [file, format("%s %02d", render_label, index + 1)] }
        cells = entries.map { |file, label| contact_cell(file, label) }
        sheet = Vips::Image.arrayjoin(
          cells, across: COLUMNS, shim: 10, background: BACKGROUND, valign: :low
        )
        sheet.write_to_file(path, Q: 92)
        File.chmod(0o600, path)
      end

      def self.contact_cell(path, label)
        tile = Vips::Image.thumbnail(path, TILE_WIDTH, height: TILE_HEIGHT)
        caption = Vips::Image.text(label, dpi: 96, font: "sans 16")
        strip = caption.embed(12, 8, tile.width, caption.height + 16)
        tile.join(strip, :vertical, expand: true, background: BACKGROUND)
      rescue Vips::Error => error
        raise Error, "cannot build contact sheet for #{File.basename(path)}: #{error.message}"
      end

      # Local screening only. A perceptual proxy flags similar compositions,
      # not interchangeable expressions. Retain every frame for human review.
      def self.screen_frames(frames)
        seen = {}
        frames.map do |frame|
          path = frame.fetch("path")
          raise Error, "frame checksum changed" unless Digest::SHA256.file(path).hexdigest == frame.fetch("sha256")

          image = Vips::Image.new_from_file(path, access: :random)
          thumbnail = image.colourspace("b-w").thumbnail_image(16, height: 16, size: :force)
          pixels = thumbnail.cast(:uchar).write_to_memory.bytes
          nearest = seen.min_by do |_, previous|
            pixels.zip(previous).sum { |a, b| (a - b).abs }
          end
          distance = nearest && pixels.zip(nearest.last).sum { |a, b| (a - b).abs }.fdiv(pixels.length * 255)
          seen[path] = pixels
          frame.merge("measurements" => Postpro::Uncanny.read_image(image).to_h,
                      "width" => image.width, "height" => image.height,
                      "similar_to" => distance && distance < 0.015 ? File.basename(nearest.first) : nil,
                      "similarity_distance" => distance,
                      "technical" => "MEASURED", "review" => "NOT_REVIEWED")
        rescue StandardError => error
          frame.merge("technical" => "INCONCLUSIVE", "reason" => error.class.name, "review" => "NOT_REVIEWED")
        end
      end

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

        # Review against photographs never used to train the adapter. A
        # training-set comparison leaks the answer and can make a weak LoRA
        # appear more faithful than it is.
        def reference_files
          Quality.evaluation_files(subject: @subject, root: @root)
        end

        def build(candidate: false, profile: nil)
          consent = Consent.require!(
            subject: @subject, subject_directory: @subject_directory, action: :training
          )
          references = reference_files
          review_consent = Consent.require!(
            subject: @subject, subject_directory: @subject_directory,
            action: :likeness_review, required_sources: ["evaluation_photographs"]
          )
          profile ||= candidate ? Quality.default_profile : latest_inference_profile
          profile = profile.to_s
          raise Error, "unknown inference profile #{profile.inspect}" unless Quality.profiles.key?(profile)

          cache = File.join(@subject_directory, ".cache")
          secure_directory!(cache)

          # Reuse the exact read-only gate used before paid training. A candidate
          # must not be generated from an incomplete, altered or unconsented set.
          require_training_ready!

          # Check the private reference set and pinned candidate before any
          # provider prediction. A bad dataset must not consume a paid sample.
          picture = Studio::Visual::IdeaPicture.new(
            subject: @subject, subjects_root: @root, lora_only: true,
            inference_profile: profile
          )
          version = picture.send(:still_model)

          render_kind = candidate ? "UNAPPROVED_CANDIDATE" : "FINAL_SERIES"
          if candidate
            output = new_review_directory(File.join(cache, "likeness-review"))
            renders = render_candidate_renders(output, profile:)
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
            "evaluation_set" => {
              "kind" => "HELD_OUT",
              "directory" => Quality.evaluation_directory_name,
              "image_count" => references.length,
              "disjoint_from_training" => true,
            },
            "inference_profile" => profile,
            "contact_sheet" => File.basename(sheet_path),
            "reference_measurements" => reference_metrics,
            "measurements" => metrics,
            "images" => images,
            "identity_assessment" => "NOT_AUTOMATED",
            "quality_rubric" => QUALITY_RUBRIC.map do |id, description|
              { "criterion" => id, "description" => description, "status" => "NOT_REVIEWED" }
            end,
            "human_review_required" => true,
            "approval_field" => "LIKELINESS_REVIEWED_VERSION",
            "approval_instruction" => "Compare every full-size render with the independent held-out evaluation photographs. Do not approve a model from the contact sheet or image-quality metrics alone.",
            "provider_predictions" => (candidate ? renders.length : 0),
            "provider_uploads" => 0,
            "consent_valid" => consent.fetch("valid"),
            "review_consent_valid" => review_consent.fetch("valid"),
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

        def render_candidate_renders(output, profile:)
          picture = Studio::Visual::IdeaPicture.new(
            subject: @subject, subjects_root: @root, directory: output,
            lora_only: true, allow_unreviewed_likeness: true,
            inference_profile: profile
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

        def latest_inference_profile
          latest = ledger_rows.reverse.find do |row|
            row["kind"] == "series_start" && row["subject"] == @subject
          end
          value = latest && latest["inference_profile"]
          Quality.profiles.key?(value.to_s) ? value.to_s : Quality.default_profile
        end

        def measure_images(paths)
          paths.map do |path|
            image = Vips::Image.new_from_file(path, access: :random)
            reading = Postpro::Uncanny.read_image(image)
            {
              "file" => File.basename(path),
              "texture" => reading.texture,
              "specular_spread" => reading.specular_spread,
              "clipping_percent" => reading.clipping,
              "tonal_range" => reading.tonal_range,
              "pixel_diagnostics" => Postpro::QualityAnalyzer.report_image(image),
            }
          end
        end

        def review_images(output, references, renders)
          entries = references.map { |path| ["HOLDOUT_REFERENCE", path] } + renders.map do |path|
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
              # The bytes the verdict was made on. If this file differs later,
              # the review no longer covers it (provenance drift).
              "sha256" => Digest::SHA256.file(path).hexdigest,
            }
          end
        end

        def write_contact_sheet(references, renders, path, render_label: "RENDER")
          Review.write_contact_sheet(references, renders, path, render_label:)
        end

        def html_document(report)
          render_rows = measurement_rows(report.fetch("measurements"))
          reference_rows = measurement_rows(report.fetch("reference_measurements"))
          render_pixel_rows = pixel_diagnostic_rows(report.fetch("measurements"))
          reference_pixel_rows = pixel_diagnostic_rows(report.fetch("reference_measurements"))
          rubric_rows = Array(report["quality_rubric"]).map do |item|
            "<li><strong>#{escape_html(item.fetch("criterion"))}</strong> — " \
              "#{escape_html(item.fetch("description"))} <em>#{escape_html(item.fetch("status"))}</em></li>"
          end.join("\n")
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
              <p class="warning">Identity and photographic verdicts: NOT REVIEWED. Compare every full-size render with the independent holdout photographs. Do not approve from a contact sheet or image metrics alone.</p>
              <p>Inference profile: <code>#{escape_html(report.fetch("inference_profile", Quality.default_profile))}</code>. A profile remains experimental until reviewed against the same holdout set.</p>
              <h2>Human photographic review</h2>
              <p>Inspect every render at full size. Record each criterion as PASS, FAIL or INCONCLUSIVE outside this generated report; none is approved automatically.</p>
              <ul>#{rubric_rows}</ul>
              <img src="contact-sheet.jpg" alt="#{Integer(report.fetch("reference_count"))} held-out evaluation photographs and #{Integer(report.fetch("render_count"))} #{report.fetch("render_kind") == "UNAPPROVED_CANDIDATE" ? "candidate" : "final"} portraits">
              <h2>Full-resolution source and render files</h2>
              <div class="gallery">#{gallery}</div>
              <h2>Independent holdout measurements</h2>
              <p>Whole-frame texture, specular spread, clipping and tonal range are diagnostic proxies, not face recognition.</p>
              <table>
                <thead><tr><th>Reference</th><th>Texture</th><th>Specular spread</th><th>Clipping</th><th>Tonal range</th></tr></thead>
                <tbody>#{reference_rows}</tbody>
              </table>
              <h3>Sampled pixel diagnostics — held-out photographs</h3>
              <p>Dimensions, decoded-sRGB linear-light exposure, clipping, tonal spread and RMS contrast. These diagnostics do not assess composition, focus, expression or likeness.</p>
              <table>
                <thead><tr><th>File</th><th>Dimensions</th><th>Mean luminance</th><th>p01 / p99</th><th>Clipped highlights</th><th>Clipped shadows</th><th>Tonal spread</th><th>RMS contrast</th></tr></thead>
                <tbody>#{reference_pixel_rows}</tbody>
              </table>
              <h2>Generated image measurements</h2>
              <table>
                <thead><tr><th>File</th><th>Texture</th><th>Specular spread</th><th>Clipping</th><th>Tonal range</th></tr></thead>
                <tbody>#{render_rows}</tbody>
              </table>
              <h3>Sampled pixel diagnostics — generated portraits</h3>
              <table>
                <thead><tr><th>File</th><th>Dimensions</th><th>Mean luminance</th><th>p01 / p99</th><th>Clipped highlights</th><th>Clipped shadows</th><th>Tonal spread</th><th>RMS contrast</th></tr></thead>
                <tbody>#{render_pixel_rows}</tbody>
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

        def pixel_diagnostic_rows(rows)
          rows.map do |row|
            diagnostic = row.fetch("pixel_diagnostics")
            exposure = diagnostic.fetch(:exposure)
            tonal = diagnostic.fetch(:tonal)
            contrast = diagnostic.fetch(:contrast)
            dimensions = diagnostic.fetch(:dimensions).join(" × ")
            <<~HTML.strip
              <tr>
                <td>#{escape_html(row.fetch("file"))}</td>
                <td>#{escape_html(dimensions)}</td>
                <td>#{format("%.4f", exposure.fetch(:mean_luminance))}</td>
                <td>#{format("%.4f", exposure.fetch(:p01))} / #{format("%.4f", exposure.fetch(:p99))}</td>
                <td>#{format("%.4f", exposure.fetch(:clipped_highlights_pct))}%</td>
                <td>#{format("%.4f", exposure.fetch(:clipped_shadows_pct))}%</td>
                <td>#{format("%.4f", tonal.fetch(:histogram_spread))}</td>
                <td>#{format("%.4f", contrast.fetch(:rms_contrast))}</td>
              </tr>
            HTML
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
        options = { subject: nil, candidate: false, profile: nil }
        OptionParser.new do |parser|
          parser.banner = "Usage: ruby STUDIO/lora/review.rb --subject NAME"
          parser.on("--subject NAME", "review a subject's portraits") { |value| options[:subject] = value }
          parser.on("--candidate", "render three private LoRA samples before approving a new model") { options[:candidate] = true }
          parser.on("--profile NAME", "select a controlled inference profile (default: balanced)") { |value| options[:profile] = value }
        end.parse!(argv)
        raise ArgumentError, "--subject is required" if options[:subject].to_s.empty?

        result = Builder.new(subject: options[:subject]).build(candidate: options[:candidate], profile: options[:profile])
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
