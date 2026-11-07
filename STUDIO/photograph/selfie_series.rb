# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "pathname"
require "time"
require "tempfile"
require "yaml"

require_relative "idea_picture"

module Studio
  module Visual
    # Ten distinct selfie directions for every locally registered LoRA
    # checkpoint. Old renders are retired only when Postpro provenance and
    # both image hashes agree; ambiguous files remain untouched.
    class SelfieSeries
      SHOTS_PER_MODEL = 10
      SERIES_SCHEMA = "studio.selfie-series.v1"
      RETIREMENT_SCHEMA = "studio.selfie-retirement.v1"
      SUBJECT_ROOT = File.expand_path("../replicate/lora", __dir__)
      DEFAULT_OUTPUT = File.expand_path("~/ideas")
      SEED_BASE = 26_110_700
      SHA256 = /\A[0-9a-f]{64}\z/.freeze
      VERSION = /\A[^\/\s:]+\/[^:\s]+:[^:\s]+\z/.freeze
      STAMP = /\A\d{8}T\d{12}\z/.freeze

      SHOTS = [
        {
          id: "window_morning_portra",
          prompt: "A genuine front-camera phone selfie at arm's length beside a large apartment window on a quiet morning; relaxed unposed expression, soft directional window key from camera-left, gentle negative fill, believable room detail, natural skin and fine Portra 400-inspired color-negative response, soft highlight shoulder, no beauty lighting."
        },
        {
          id: "direct_flash_snapshot",
          prompt: "A spontaneous mirror selfie in a small lived-in apartment at night, phone and hand naturally visible; direct on-camera flash, crisp near shadow on the wall, fast falloff into a dark room, candid late-1990s snapshot energy, neutral skin under flash, saturated but controlled background, visible fine analog grain and honest imperfections."
        },
        {
          id: "rainy_neon_street",
          prompt: "A close front-camera selfie outdoors on a rainy city street after dark, wet pavement and shop practicals behind; mixed red, green and cool-blue reflections, face lit by a plausible nearby storefront, deep but readable shadows, tungsten-negative-inspired color separation, restrained halation only around real lights, no generic teal-orange grade."
        },
        {
          id: "nordic_fjord_overcast",
          prompt: "A casual arm's-length selfie on a windy Nordic waterfront beneath a bright overcast sky; fjord and distant mountains softly readable behind, cool-neutral ambient light with accurate warm skin, wind-moved hair, natural asymmetry, documentary 250D-inspired daylight-negative color, delicate fine grain, no fake fog."
        },
        {
          id: "golden_hour_backlight",
          prompt: "A handheld front-camera selfie outdoors just before sunset, low sun behind and slightly to one side, soft sky fill on the face, warm rim through hair, believable flare only if the sun crosses the lens, warm highlights without orange skin, cooler open-shade shadows, rich Portra-like negative color."
        },
        {
          id: "tungsten_cafe_candid",
          prompt: "A genuine close selfie at a busy cafe table after dark, amber pendant lamps and a few practicals behind, tungsten key motivated by the nearest lamp, small natural eye catchlights, shadow side retains shape, warm interior with cooler window ambience, 500T-inspired grain and highlight halation kept local."
        },
        {
          id: "tri_x_sidewalk",
          prompt: "A black-and-white front-camera street selfie in hard late-afternoon side light, strong sculptural shadow across the background, natural candid expression, crisp eyes, rich silver-gelatin-like blacks and textured midtones, Tri-X 400-inspired panchromatic tonality and visible organic grain, no scratches or fake film damage."
        },
        {
          id: "fluorescent_transit",
          prompt: "A front-camera selfie inside a modern train or tram at night, cool fluorescent ceiling practicals and passing city lights through the window, mixed-source skin color handled naturally, documentary framing with a little motion in the background but sharp eyes, restrained green-cyan ambience, realistic reflections and no artificial bokeh."
        },
        {
          id: "bright_summer_ektar",
          prompt: "A bright summer holiday selfie in open shade near the sea, hard sun and sparkling water in the background, clear blue sky, natural skin hue held apart from vivid environment colors, crisp daylight and fine-grain Ektar-inspired color-negative character, realistic highlights and no clipped face."
        },
        {
          id: "low_key_editorial",
          prompt: "A moody front-camera selfie in a quiet backstage corridor, one large soft practical source shaping the face from the side, deep negative fill, a dim secondary light receding behind, precise eye focus, controlled blacks, neutral skin, editorial low-key chiaroscuro and subtle fine film texture without glamour retouching."
        }
      ].map { |shot| shot.freeze }.freeze

      def initialize(
        client: nil,
        subjects_directory: SUBJECT_ROOT,
        output_directory: DEFAULT_OUTPUT,
        picture_class: Studio::Visual::IdeaPicture,
        clock: -> { Time.now.utc }
      )
        @client = client
        @subjects_directory = File.expand_path(subjects_directory)
        @output_directory = File.expand_path(output_directory)
        @picture_class = picture_class
        @clock = clock
      end

      def write
        models = discover_models!
        ensure_provider_access!
        ensure_output_root!
        run_id = @clock.call.utc.strftime("%Y%m%dT%H%M%S%6N")
        run_directory = File.join(@output_directory, "selfie-series-#{run_id}")
        raise ArgumentError, "selfie series already exists: #{run_directory}" if File.exist?(run_directory) || File.symlink?(run_directory)

        retire_previous_renders!
        FileUtils.mkdir_p(run_directory, mode: 0o700)
        File.chmod(0o700, run_directory)
        manifest_path = File.join(run_directory, ".studio-selfie-series.json")
        series = {
          "schema" => SERIES_SCHEMA,
          "run_id" => run_id,
          "created_at" => @clock.call.utc.iso8601,
          "status" => "running",
          "requested_per_model" => SHOTS_PER_MODEL,
          "curation_status" => "pending_operator_review",
          "shot_ids" => SHOTS.map { |shot| shot.fetch(:id) },
          "models" => models.map do |model|
            {
              "subject" => model.fetch(:subject),
              "model_slug" => model.fetch(:slug),
              "model_version" => model.fetch(:version),
              "directory" => File.join(model.fetch(:subject), model.fetch(:slug)),
              "status" => "pending",
              "curation_status" => "pending_operator_review",
              "renders" => [],
              "failures" => []
            }
          end
        }
        write_private_json(manifest_path, series)

        fatal = nil
        models.each_with_index do |model, model_index|
          model_record = series.fetch("models").fetch(model_index)
          model_directory = File.join(run_directory, model.fetch(:subject), model.fetch(:slug))
          ensure_private_directory!(File.dirname(model_directory))
          ensure_private_directory!(model_directory)
          picture = @picture_class.new(
            client: client,
            directory: model_directory,
            subject: model.fetch(:subject),
            model_manifest: model.fetch(:manifest)
          )

          SHOTS.each_with_index do |shot, index|
            seed = SEED_BASE + index
            begin
              result = picture.write(shot.fetch(:prompt), film: false, seed:)
              render = verify_render!(result, model_directory)
              model_record.fetch("renders") << {
                "shot_id" => shot.fetch(:id),
                "review_status" => "pending_operator_review",
                "seed" => seed,
                "prompt" => shot.fetch(:prompt),
                "source" => relative_to(run_directory, render.fetch(:source)),
                "image" => relative_to(run_directory, render.fetch(:image)),
                "sidecar" => relative_to(run_directory, render.fetch(:sidecar)),
                "source_sha256" => render.fetch(:source_sha256),
                "image_sha256" => render.fetch(:image_sha256),
                "sidecar_sha256" => Digest::SHA256.file(render.fetch(:sidecar)).hexdigest
              }
              model_record["status"] = "running"
            rescue StandardError => error
              model_record.fetch("failures") << {
                "shot_id" => shot.fetch(:id),
                "error" => "#{error.class}: #{error.message}"
              }
              if fatal_provider_error?(error)
                fatal = error
                break
              end
            ensure
              write_private_json(manifest_path, series)
            end
          end

          unless model_record.fetch("renders").empty?
            contact_sheet = write_contact_sheet!(model_directory, model_record)
            model_record["contact_sheet"] = relative_to(run_directory, contact_sheet)
            model_record["contact_sheet_sha256"] = Digest::SHA256.file(contact_sheet).hexdigest
          end

          model_record["status"] = if model_record.fetch("renders").length == SHOTS_PER_MODEL
                                     "complete"
                                   elsif model_record.fetch("renders").empty?
                                     "failed"
                                   else
                                     "partial"
                                   end
          write_private_json(manifest_path, series)
          break if fatal
        end

        series["status"] = if fatal
                             "blocked"
                           elsif series.fetch("models").all? { |row| row.fetch("status") == "complete" }
                             "complete"
                           else
                             "partial"
                           end
        series["finished_at"] = @clock.call.utc.iso8601
        write_private_json(manifest_path, series)

        {
          "status" => series.fetch("status"),
          "run_id" => run_id,
          "manifest" => manifest_path,
          "curation_status" => series.fetch("curation_status"),
          "models" => series.fetch("models").map do |row|
            {
              "subject" => row.fetch("subject"),
              "model_slug" => row.fetch("model_slug"),
              "model_version" => row.fetch("model_version"),
              "status" => row.fetch("status"),
              "renders" => row.fetch("renders").length,
              "failures" => row.fetch("failures").length
            }
          end,
          "retired" => @retirement_report
        }
      ensure
        write_private_json(manifest_path, series) if manifest_path && series
      end

      private

      # Authenticate with a read-only API request before touching old renders.
      # A token's presence proves neither validity nor access; a rejected token
      # must not leave the previous render set retired with no replacement.
      def ensure_provider_access!
        if @client.nil? && Studio::ReplicateClient.load_token.to_s.strip.empty?
          raise ArgumentError,
                "missing REPLICATE_API_TOKEN; set it or configure ~/.config/replicate/config.json before retiring old renders or generating selfies"
        end

        response = client.models(limit: 1)
        raise TypeError, "Replicate model preflight did not return a list" unless response.is_a?(Array)

        true
      rescue StandardError => error
        raise if error.is_a?(ArgumentError) && error.message.start_with?("missing REPLICATE_API_TOKEN")

        raise ArgumentError,
              "Replicate access preflight failed before retiring old renders: #{error.class}: #{error.message}"
      end

      def client
        @client ||= Studio::ReplicateClient.new
      end

      def discover_models!
        raise ArgumentError, "LoRA subject directory is missing: #{@subjects_directory}" unless File.directory?(@subjects_directory)

        manifests = Dir.glob(File.join(@subjects_directory, "*", "weights", "*", "replicate_training.json")).sort
        if manifests.empty?
          raise ArgumentError,
                "no LoRA model manifests found under #{@subjects_directory}; expected <subject>/weights/<model>/replicate_training.json"
        end

        manifests.map { |path| validate_model!(path) }
      end

      def validate_model!(path)
        subject_directory = File.dirname(File.dirname(File.dirname(path)))
        subject = File.basename(subject_directory)
        slug = File.basename(File.dirname(path))
        raise ArgumentError, "invalid LoRA subject directory name: #{subject}" unless subject.match?(/\A[a-zA-Z0-9_-]+\z/)
        raise ArgumentError, "invalid LoRA model directory name: #{slug}" unless slug.match?(/\A[a-zA-Z0-9_.-]+\z/)

        validate_private_directory!(subject_directory)
        weights_directory = File.dirname(File.dirname(path))
        validate_private_directory!(weights_directory)
        validate_private_file!(File.join(subject_directory, "subject.env"), "subject.env")
        environment = parse_subject_env(File.join(subject_directory, "subject.env"))
        raise ArgumentError, "#{subject}/subject.env must set TRIGGER" if environment.fetch("TRIGGER", "").strip.empty?
        validate_consent!(subject, File.join(subject_directory, "consent.yml"))

        validate_private_directory!(File.dirname(path))
        validate_private_file!(path, "model manifest")
        document = JSON.parse(File.read(path, encoding: "UTF-8"))
        version = document["version"].to_s
        raise ArgumentError, "invalid model version in #{path}; expected owner/model:version" unless version.match?(VERSION)

        {
          subject: subject,
          slug: slug,
          version: version,
          manifest: path
        }
      rescue JSON::ParserError => error
        raise ArgumentError, "invalid LoRA model manifest #{path}: #{error.message}"
      end

      def parse_subject_env(path)
        File.foreach(path, encoding: "UTF-8").each_with_object({}) do |line, values|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          key, value = line.split("=", 2)
          next unless key && value

          values[key.strip] = value.strip.delete_prefix('"').delete_suffix('"')
        end
      end

      def validate_consent!(subject, path)
        validate_private_file!(path, "consent record")
        record = YAML.safe_load(File.read(path, encoding: "UTF-8"), permitted_classes: [], aliases: false)
        raise ArgumentError, "unsupported consent record schema for #{subject}" unless record.is_a?(Hash) && record["schema"] == 1
        raise ArgumentError, "consent record subject mismatch for #{subject}" unless record["subject"] == subject

        person = record["subject_consent"]
        rights = record["source_rights"]
        unless person.is_a?(Hash) && person["likeness_generation"] == true && person["provider_processing"] == true
          raise ArgumentError, "#{subject}: likeness generation and provider processing consent are not verified"
        end
        unless rights.is_a?(Hash) && rights["generation_use"] == true &&
               rights["provider_processing"] == true && rights["evidence"].to_s.strip.length >= 8
          raise ArgumentError, "#{subject}: source rights and provider-processing evidence are not verified"
        end
      rescue Psych::Exception => error
        raise ArgumentError, "invalid consent YAML for #{subject}: #{error.message}"
      end

      def validate_private_file!(path, label)
        stat = File.lstat(path)
        raise ArgumentError, "#{label} must be a regular non-symlink file: #{path}" unless stat.file? && !stat.symlink?
        raise ArgumentError, "#{label} must be owned by the current user: #{path}" unless stat.uid == Process.uid
        raise ArgumentError, "#{label} must have owner-only permissions (0600): #{path}" unless (stat.mode & 0o077).zero?
        raise ArgumentError, "#{label} is too large: #{path}" if stat.size > 65_536
        true
      rescue Errno::ENOENT
        raise ArgumentError, "missing #{label}: #{path}"
      end

      def validate_private_directory!(path)
        stat = File.lstat(path)
        raise ArgumentError, "private model directory must be a real directory: #{path}" unless stat.directory? && !stat.symlink?
        raise ArgumentError, "private model directory must be owned by the current user: #{path}" unless stat.uid == Process.uid
        raise ArgumentError, "private model directory must have owner-only permissions (0700): #{path}" unless (stat.mode & 0o077).zero?
        true
      end

      def ensure_output_root!
        if Studio::OutputPaths.inside_repository?(@output_directory)
          raise ArgumentError, "selfie-series output must remain outside the repository checkout"
        end

        unless File.exist?(@output_directory)
          FileUtils.mkdir_p(@output_directory, mode: 0o700)
          File.chmod(0o700, @output_directory)
        end
        stat = File.lstat(@output_directory)
        raise ArgumentError, "output directory must not be a symlink" if stat.symlink?
        raise ArgumentError, "output path must be a directory" unless stat.directory?
        raise ArgumentError, "output directory must be owned by the current user" unless stat.uid == Process.uid

        # This directory contains faces, generated images and their source
        # renders. Tighten an existing owner-owned directory rather than
        # inheriting group/world readability from an old ~/ideas folder.
        File.chmod(0o700, @output_directory) unless (stat.mode & 0o077).zero?
        stat = File.lstat(@output_directory)
        raise ArgumentError, "output directory must be private (mode 0700)" unless (stat.mode & 0o077).zero?
        @output_directory = File.realpath(@output_directory)
      end

      def ensure_private_directory!(path)
        FileUtils.mkdir_p(path, mode: 0o700)
        stat = File.lstat(path)
        raise ArgumentError, "private output directory must not be a symlink: #{path}" if stat.symlink?
        raise ArgumentError, "private output directory must be owned by the current user: #{path}" unless stat.uid == Process.uid
        raise ArgumentError, "private output directory must have mode 0700: #{path}" unless (stat.mode & 0o077).zero?
      end

      def retire_previous_renders!
        @retirement_report = { "archived_families" => 0, "archived_files" => 0, "unverified_legacy_files" => [] }
        archive_directory = File.join(@output_directory, ".retired")
        previous_series = Dir.glob(File.join(@output_directory, "selfie-series-*")).select do |path|
          managed_series_directory?(path)
        end
        legacy_families = verified_legacy_families
        legacy_files = legacy_families.flatten.uniq
        orphan_candidates = [
          *Dir.glob(File.join(@output_directory, "*")),
          *Dir.glob(File.join(@output_directory, "postpro_*.jpg")),
          *Dir.glob(File.join(@output_directory, "postpro_*.jpg.json"))
        ].uniq
        orphans = orphan_candidates.select do |path|
          File.file?(path) && !legacy_files.include?(path) &&
            (File.basename(path).match?(/\A\d{8}T\d{12}\.(?:jpg|mp4)\z/) ||
             File.basename(path).start_with?("postpro_"))
        end
        @retirement_report["unverified_legacy_files"] = orphans.map { |path| File.basename(path) }

        return if previous_series.empty? && legacy_families.empty?

        ensure_private_directory!(archive_directory)
        archive_run = File.join(archive_directory, @clock.call.utc.strftime("%Y%m%dT%H%M%S%6N"))
        ensure_private_directory!(archive_run)
        moved = []
        begin
          previous_series.each do |path|
            destination = File.join(archive_run, File.basename(path))
            raise ArgumentError, "archive destination exists: #{destination}" if File.exist?(destination)
            File.rename(path, destination)
            moved << [path, destination]
            Dir.glob(File.join(destination, "**", "*"), File::FNM_DOTMATCH).each do |child|
              next if %w[. ..].include?(File.basename(child)) || File.directory?(child)
              File.chmod(0o600, child)
            end
          end
          legacy_files.each do |path|
            destination = File.join(archive_run, File.basename(path))
            raise ArgumentError, "archive destination exists: #{destination}" if File.exist?(destination)
            File.rename(path, destination)
            File.chmod(0o600, destination)
            moved << [path, destination]
          end
          write_private_json(
            File.join(archive_run, "retirement.json"),
            {
              "schema" => RETIREMENT_SCHEMA,
              "created_at" => @clock.call.utc.iso8601,
              "previous_series" => previous_series.map { |path| File.basename(path) },
              "files" => moved.filter_map do |original, destination|
                next unless File.file?(destination)
                {
                  "from" => original,
                  "to" => destination,
                  "sha256" => Digest::SHA256.file(destination).hexdigest
                }
              end,
              "unverified_legacy_files_left_in_place" => @retirement_report["unverified_legacy_files"]
            }
          )
        rescue StandardError
          moved.reverse_each do |original, destination|
            File.rename(destination, original) if File.exist?(destination) && !File.exist?(original)
          rescue SystemCallError
            nil
          end
          raise
        end
        @retirement_report["archived_families"] = legacy_families.length + previous_series.length
        @retirement_report["archived_files"] = moved.length
        @retirement_report["archive_directory"] = archive_run
      end

      def managed_series_directory?(path)
        stat = File.lstat(path)
        return false unless stat.directory? && !stat.symlink? && stat.uid == Process.uid
        return false unless (stat.mode & 0o077).zero?

        root = File.realpath(path)
        marker = File.join(root, ".studio-selfie-series.json")
        marker_stat = File.lstat(marker)
        return false unless marker_stat.file? && !marker_stat.symlink? && marker_stat.uid == Process.uid
        return false unless (marker_stat.mode & 0o077).zero? && marker_stat.size <= 1_048_576

        record = JSON.parse(File.read(marker, encoding: "UTF-8"))
        return false unless record["schema"] == SERIES_SCHEMA
        return false unless record["models"].is_a?(Array) && record["requested_per_model"] == SHOTS_PER_MODEL

        expected = [marker]
        record.fetch("models").each do |model|
          return false unless model.is_a?(Hash) && model["renders"].is_a?(Array)
          if model["contact_sheet"]
            sheet = File.expand_path(model["contact_sheet"].to_s, root)
            return false unless sheet.start_with?("#{root}#{File::SEPARATOR}")
            return false unless valid_private_render_file?(sheet)
            return false unless (File.stat(sheet).mode & 0o077).zero?
            sheet_digest = model.fetch("contact_sheet_sha256").to_s
            return false unless sheet_digest.match?(SHA256)
            return false unless Digest::SHA256.file(sheet).hexdigest == sheet_digest
            expected << sheet
          end
          model.fetch("renders").each do |render|
            return false unless render.is_a?(Hash)
            {
              "source" => "source_sha256",
              "image" => "image_sha256",
              "sidecar" => "sidecar_sha256"
            }.each do |relative_key, digest_key|
              relative = render.fetch(relative_key).to_s
              return false if relative.empty? || Pathname.new(relative).absolute?
              candidate = File.expand_path(relative, root)
              return false unless candidate.start_with?("#{root}#{File::SEPARATOR}")
              return false unless valid_private_render_file?(candidate)
              return false unless (File.stat(candidate).mode & 0o077).zero?
              expected_digest = render.fetch(digest_key).to_s
              return false unless expected_digest.match?(SHA256)
              return false unless Digest::SHA256.file(candidate).hexdigest == expected_digest
              expected << candidate
            end
          end
        end

        actual_files = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).reject do |candidate|
          %w[. ..].include?(File.basename(candidate))
        end
        actual_files.each do |candidate|
          child_stat = File.lstat(candidate)
          return false if child_stat.symlink?
          if child_stat.directory?
            return false unless child_stat.uid == Process.uid && (child_stat.mode & 0o077).zero?
          else
            return false unless child_stat.file? && expected.include?(candidate)
          end
        end
        (expected - actual_files).empty?
      rescue JSON::ParserError, KeyError, SystemCallError, ArgumentError
        false
      end

      def verified_legacy_families
        Dir.glob(File.join(@output_directory, "postpro_*.jpg.json")).filter_map do |sidecar_path|
          next unless valid_private_render_file?(sidecar_path)

          sidecar = JSON.parse(File.read(sidecar_path, encoding: "UTF-8"))
          next unless %w[postpro.grade.v2 postpro.chain.v1].include?(sidecar["schema"])

          input_path = File.expand_path(sidecar["input"].to_s)
          output_path = File.expand_path(sidecar["output"].to_s)
          next unless File.dirname(input_path) == @output_directory &&
                      File.dirname(output_path) == @output_directory
          next unless File.basename(input_path).match?(/\A\d{8}T\d{12}\.jpg\z/)
          next unless File.basename(output_path).start_with?("postpro_#{File.basename(input_path, ".jpg")}_")
          next unless output_path == File.expand_path(sidecar_path.delete_suffix(".json"))
          next unless valid_private_render_file?(input_path) && valid_private_render_file?(output_path)
          next unless sidecar["input_sha256"].to_s.match?(SHA256) && sidecar["output_sha256"].to_s.match?(SHA256)
          next unless Digest::SHA256.file(input_path).hexdigest == sidecar["input_sha256"]
          next unless Digest::SHA256.file(output_path).hexdigest == sidecar["output_sha256"]

          [input_path, output_path, sidecar_path]
        rescue JSON::ParserError, SystemCallError
          nil
        end
      end

      def valid_private_render_file?(path)
        stat = File.lstat(path)
        stat.file? && !stat.symlink? && stat.uid == Process.uid &&
          File.realpath(path).start_with?("#{@output_directory}#{File::SEPARATOR}")
      rescue SystemCallError
        false
      end

      def write_contact_sheet!(directory, model_record)
        path = File.join(directory, "contact-sheet.html")
        cells = model_record.fetch("renders").map do |render|
          image_name = File.basename(render.fetch("image"))
          [
            "<article class=\"shot\">",
            "<a href=\"#{CGI.escapeHTML(image_name)}\"><img loading=\"lazy\" src=\"#{CGI.escapeHTML(image_name)}\" alt=\"#{CGI.escapeHTML(render.fetch("shot_id"))}\"></a>",
            "<h2>#{CGI.escapeHTML(render.fetch("shot_id").tr("_", " "))}</h2>",
            "<p>Seed #{Integer(render.fetch("seed"))}</p>",
            "<p>#{CGI.escapeHTML(render.fetch("prompt"))}</p>",
            "<p class=\"review\">PENDING OPERATOR REVIEW</p>",
            "</article>"
          ].join("\n")
        end
        html = [
          "<!doctype html>",
          "<html lang=\"en\">",
          "<head>",
          "<meta charset=\"utf-8\">",
          "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
          "<title>#{CGI.escapeHTML(model_record.fetch("subject"))} / #{CGI.escapeHTML(model_record.fetch("model_slug"))} — selfie series</title>",
          "<style>",
          "body{margin:0;padding:24px;background:#161616;color:#eee;font:16px/1.5 system-ui,sans-serif}",
          "header{max-width:1600px;margin:0 auto 24px}",
          ".grid{max-width:1600px;margin:auto;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}",
          ".shot{min-width:0;background:#242424;padding:12px;border:1px solid #444}",
          "img{display:block;width:100%;height:auto;aspect-ratio:2/3;object-fit:cover;background:#111}",
          "h2{font-size:16px;text-transform:capitalize;margin:12px 0 4px}",
          "p{font-size:13px;color:#ccc;overflow-wrap:anywhere}",
          ".review{color:#e7c98d;font-weight:700;letter-spacing:.04em}",
          "</style>",
          "</head>",
          "<body>",
          "<header>",
          "<h1>#{CGI.escapeHTML(model_record.fetch("subject"))} · #{CGI.escapeHTML(model_record.fetch("model_slug"))}</h1>",
          "<p>Model #{CGI.escapeHTML(model_record.fetch("model_version"))} · #{model_record.fetch("renders").length} renders · pending operator review</p>",
          "</header>",
          "<main class=\"grid\">",
          cells.join("\n"),
          "</main>",
          "</body>",
          "</html>"
        ].join("\n")
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(html)
          file.flush
          file.fsync
        end
        File.chmod(0o600, path)
        path
      end

      def verify_render!(result, model_directory)
        raise ArgumentError, "image generator did not return a final still" unless result.is_a?(Hash)

        image = File.expand_path(result.fetch("still").to_s)
        sidecar = "#{image}.json"
        sidecar_data = JSON.parse(File.read(sidecar, encoding: "UTF-8"))
        source = File.expand_path(sidecar_data.fetch("input").to_s)
        raise ArgumentError, "render output is outside its private model directory" unless File.dirname(image) == model_directory
        raise ArgumentError, "render source is outside its private model directory" unless File.dirname(source) == model_directory
        raise ArgumentError, "render sidecar schema is not a Postpro grade" unless %w[postpro.grade.v2 postpro.chain.v1].include?(sidecar_data["schema"])
        raise ArgumentError, "Postpro sidecar output path does not match the rendered still" unless File.expand_path(sidecar_data.fetch("output")) == image
        raise ArgumentError, "render source is missing" unless valid_private_render_file?(source)
        raise ArgumentError, "render output is missing or empty" unless valid_private_render_file?(image) && File.size(image).positive?
        raise ArgumentError, "render sidecar is missing" unless valid_private_render_file?(sidecar)
        raise ArgumentError, "render source hash does not match the sidecar" unless Digest::SHA256.file(source).hexdigest == sidecar_data.fetch("input_sha256")
        raise ArgumentError, "render output hash does not match the sidecar" unless Digest::SHA256.file(image).hexdigest == sidecar_data.fetch("output_sha256")

        [source, image, sidecar].each { |file| File.chmod(0o600, file) }
        {
          source: source,
          image: image,
          sidecar: sidecar,
          source_sha256: Digest::SHA256.file(source).hexdigest,
          image_sha256: Digest::SHA256.file(image).hexdigest
        }
      rescue KeyError, JSON::ParserError => error
        raise ArgumentError, "incomplete Postpro render receipt: #{error.message}"
      end

      def relative_to(root, path)
        path.delete_prefix("#{root}#{File::SEPARATOR}")
      end

      def write_private_json(path, value)
        Tempfile.create([".selfie-series-", ".json"], File.dirname(path), mode: 0o600) do |file|
          file.write(JSON.pretty_generate(value))
          file.write("\n")
          file.flush
          file.fsync
          File.chmod(0o600, file.path)
          file.close
          File.rename(file.path, path)
        end
      end

      def fatal_provider_error?(error)
        error.is_a?(Studio::ReplicateClient::ExhaustedError) ||
          error.is_a?(Studio::ReplicateClient::TransientError) ||
          error.message.match?(/\b(?:400|401|402|403|404|422)\b|unprocessable|invalid input|unknown field|schema|insufficient credits|billing|quota exhausted|budget exhausted|missing REPLICATE_API_TOKEN/i)
      end
    end
  end
end
