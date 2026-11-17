# frozen_string_literal: true

module Master
  module Fix
    class SurfaceEvidence
      # Receipt builders for the filesystem-derived surfaces: the bounded
      # inventory census, path and file-name receipts, the literal relative
      # dependency graph, media signatures and the generated asset contract.
      private

      def tree_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        receipt("assessed_clean", evidence: {
          "method" => "bounded no-follow filesystem inventory plus FixPlan source digests",
          "target" => @target_label,
          "inventory_sha256" => inventory["digest"],
          "source_sha256" => source["digest"],
          "excluded_directory_count" => inventory["ignored_directories"].size,
          "symlink_count" => inventory["symlinks"],
        }, counts: {
          "files" => inventory["files"],
          "directories" => inventory["directories"],
          "symlinks" => inventory["symlinks"],
        })
      end

      def directory_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        receipt("assessed_clean", evidence: {
          "method" => "parent-directory census over the same no-follow inventory",
          "inventory_sha256" => inventory["digest"],
          "source_sha256" => source["digest"],
        }, counts: { "directories" => inventory["directories"] })
      end

      def file_name_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        names = inventory["records"].filter_map { |row| row[0] if row[1] == "file" }.map { |path| File.basename(path) }.sort
        receipt("assessed_clean", evidence: {
          "method" => "complete eligible and non-binary file-name inventory",
          "names_sha256" => digest_json(names),
          "source_sha256" => source["digest"],
        }, counts: { "file_names" => names.size })
      end

      def path_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        paths = inventory["records"].map(&:first).sort
        receipt("assessed_clean", evidence: {
          "method" => "relative path inventory; symlinks are recorded but never followed",
          "paths_sha256" => digest_json(paths),
          "source_sha256" => source["digest"],
        }, counts: { "paths" => paths.size })
      end

      def cross_file_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        edges = []
        unresolved = []
        unreadable = []
        text_paths = cross_file_text_paths
        text_paths.each { |path| collect_cross_file_edges(path, edges, unresolved, unreadable) }

        return cross_file_unreadable_receipt(unreadable) if unreadable.any?
        return cross_file_unresolved_receipt(unresolved, source) if unresolved.any?

        receipt("assessed_clean", evidence: {
          "method" => "resolved literal relative dependency graph",
          "edge_sha256" => digest_json(edges.sort),
          "source_sha256" => source["digest"],
        }, counts: { "source_files" => text_paths.size, "resolved_edges" => edges.size })
      end

      def cross_file_text_paths
        @plan.sources.filter_map do |item|
          path = File.expand_path(item.path, @root)
          path if File.file?(path) && !File.symlink?(path) && File.extname(path).downcase.match?(
            /\A\.(?:rb|rake|gemspec|js|mjs|cjs|ts|tsx|jsx|css|scss|sass|html|erb)\z/,
          )
        end.sort
      end

      def collect_cross_file_edges(path, edges, unresolved, unreadable)
        body = read_stable(path)
        unless body
          unreadable << relative(path)
          return
        end

        collect_ruby_edges(path, body, edges, unresolved)
        collect_module_edges(path, body, edges, unresolved)
      end

      def collect_ruby_edges(path, body, edges, unresolved)
        extension = File.extname(path).downcase
        return unless extension == ".rb" || extension == ".rake" || extension == ".gemspec"

        body.to_enum(:scan, %r{require_relative\s*[\(\s]*["']([^"']+)["']}).each do
          reference = Regexp.last_match(1)
          destination = ruby_reference_candidates(path, reference).find do |candidate|
            File.file?(candidate) && !File.symlink?(candidate)
          end
          if destination
            edges << [relative(path), relative(destination), "require_relative"]
          else
            unresolved << { "source" => relative(path), "reference" => reference, "kind" => "require_relative" }
          end
        end
      end

      def collect_module_edges(path, body, edges, unresolved)
        extension = File.extname(path).downcase
        return unless %w[.js .mjs .cjs .ts .tsx .jsx].include?(extension)

        body.to_enum(:scan, %r{(?:from\s*|import\s*\()\s*["'](\.{1,2}/[^"']+)["']}).each do
          reference = Regexp.last_match(1)
          destination = module_reference_candidates(path, reference).find do |candidate|
            File.file?(candidate) && !File.symlink?(candidate)
          end
          if destination
            edges << [relative(path), relative(destination), "module_import"]
          else
            unresolved << { "source" => relative(path), "reference" => reference, "kind" => "module_import" }
          end
        end
      end

      def cross_file_unreadable_receipt(unreadable)
        receipt("inconclusive", reason: "cross-file source reads failed for #{unreadable.first(4).join(', ')}")
      end

      def cross_file_unresolved_receipt(unresolved, source)
        receipt("violation_found",
          reason: "unresolved local references: #{unresolved.first(4).map { |row| "#{row["source"]} -> #{row["reference"]}" }.join(", ")}",
          findings: unresolved.first(40),
          evidence: { "method" => "resolved literal relative dependencies", "source_sha256" => source["digest"] })
      end

      def media_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)

        asset_records = recognized_asset_records(inventory)
        return media_empty_receipt(inventory) if asset_records.empty?

        measured, failures, unmeasured = measure_media_assets(asset_records)
        return media_failure_receipt(failures, inventory) if failures.any?
        return media_unmeasured_receipt(unmeasured, inventory) if unmeasured.any?

        receipt("assessed_clean", evidence: {
          "method" => "signature-checked asset inventory; no image content or accessibility inference",
          "asset_manifest_sha256" => digest_json(measured.sort),
          "inventory_sha256" => inventory["digest"],
        }, counts: { "assets" => measured.size })
      end

      def media_empty_receipt(inventory)
        receipt("not_applicable", reason: "target inventory contains no recognized media or font assets",
          evidence: { "method" => "complete target inventory", "inventory_sha256" => inventory["digest"] })
      end

      def measure_media_assets(asset_records)
        assets = asset_records.select { |_path, type, _size| type == "file" }
        unmeasured = asset_records.select { |_path, type, _size| type == "symlink" }.map do |path, _type, _size|
          "#{path} (symlink target not verified)"
        end
        failures = []
        measured = []
        assets.each { |relative_path, _type, expected_bytes| measure_media_asset(relative_path, expected_bytes, measured, failures, unmeasured) }
        [measured, failures, unmeasured]
      end

      def measure_media_asset(relative_path, expected_bytes, measured, failures, unmeasured)
        path = File.expand_path(relative_path, @root)
        return if File.symlink?(path) || !File.file?(path)

        stat = File.stat(path)
        if stat.size <= 0 || stat.size != expected_bytes
          failures << { "path" => relative_path, "reason" => "empty or unstable asset size" }
          return
        end
        header = File.open(path, "rb") { |file| file.read(4096).to_s }
        kind = asset_kind(File.extname(path).downcase, header)
        if kind == :valid
          measured << [relative_path, Digest::SHA256.file(path).hexdigest, stat.size]
        elsif kind == :invalid
          failures << { "path" => relative_path, "reason" => "asset signature does not match extension" }
        else
          unmeasured << relative_path
        end
      rescue StandardError => e
        unmeasured << "#{relative_path} (#{e.class})"
      end

      def media_failure_receipt(failures, inventory)
        receipt("violation_found", reason: "invalid media assets: #{failures.first(4).map { |row| row["path"] }.join(", ")}",
          findings: failures.first(40), evidence: { "method" => "file signature and byte stability", "inventory_sha256" => inventory["digest"] })
      end

      def media_unmeasured_receipt(unmeasured, inventory)
        receipt("inconclusive", reason: "asset type or read could not be verified: #{unmeasured.first(4).join(", ")}",
          evidence: { "method" => "file signature and byte stability", "inventory_sha256" => inventory["digest"] })
      end

      def recognized_asset_records(inventory)
        Array(inventory["records"]).select do |path, type, _size|
          %w[file symlink].include?(type) && MEDIA_EXTENSIONS.include?(File.extname(path.to_s).downcase)
        end
      end

      def asset_kind(extension, header)
        kind = fixed_header_asset_kind(extension, header)
        return kind if kind

        structured_header_asset_kind(extension, header) || :unknown
      end

      def fixed_header_asset_kind(extension, header)
        case extension
        when ".png" then header.start_with?("\x89PNG\r\n\x1a\n".b) ? :valid : :invalid
        when ".jpg", ".jpeg" then header.start_with?("\xFF\xD8\xFF".b) ? :valid : :invalid
        when ".gif" then header.start_with?("GIF87a", "GIF89a") ? :valid : :invalid
        when ".ico" then header.start_with?("\x00\x00\x01\x00".b) ? :valid : :invalid
        when ".bmp" then header.start_with?("BM") ? :valid : :invalid
        when ".tif", ".tiff" then header.start_with?("II*\x00".b, "MM\x00*".b) ? :valid : :invalid
        when ".pdf" then header.start_with?("%PDF-") ? :valid : :invalid
        when ".flac" then header.start_with?("fLaC") ? :valid : :invalid
        when ".ogg" then header.start_with?("OggS") ? :valid : :invalid
        when ".woff" then header.start_with?("wOFF") ? :valid : :invalid
        when ".woff2" then header.start_with?("wOF2") ? :valid : :invalid
        when ".ttf" then header.start_with?("\x00\x01\x00\x00".b, "true") ? :valid : :invalid
        when ".otf" then header.start_with?("OTTO") ? :valid : :invalid
        when ".webm" then header.start_with?("\x1A\x45\xDF\xA3".b) ? :valid : :invalid
        end
      end

      def structured_header_asset_kind(extension, header)
        case extension
        when ".webp" then header.bytesize >= 12 && header.start_with?("RIFF") && header.byteslice(8, 4) == "WEBP" ? :valid : :invalid
        when ".avif", ".mp4", ".mov", ".m4a" then header.bytesize >= 12 && header.byteslice(4, 4) == "ftyp" ? :valid : :invalid
        when ".svg"
          normalized = header.delete_prefix("\uFEFF").lstrip
          normalized.match?(%r{(?:\A<svg\b)|(?:\A<\?xml\b.*?<svg\b)}mi) ? :valid : :invalid
        when ".wav" then header.bytesize >= 12 && header.start_with?("RIFF") && header.byteslice(8, 4) == "WAVE" ? :valid : :invalid
        when ".mp3" then header.start_with?("ID3") || header.getbyte(0) == 0xFF && (header.getbyte(1).to_i & 0xE0) == 0xE0 ? :valid : :invalid
        when ".aac" then header.start_with?("ID3") || header.getbyte(0) == 0xFF && (header.getbyte(1).to_i & 0xF6) == 0xF0 ? :valid : :invalid
        end
      end

      def compiled_asset_receipt(inventory, source)
        return receipt("inconclusive", reason: inventory["reason"] || source["reason"]) unless captured?(inventory, source)
        return receipt("not_applicable", reason: "target is outside the Rails asset build surface") unless rails_target?

        begin
          compiled_asset_check_receipt
        rescue StandardError => e
          receipt("inconclusive", reason: "generated asset checker unavailable: #{error_text(e)}")
        end
      end

      def compiled_asset_check_receipt
        require_relative "../../../checks/lib/source/generated_asset" unless defined?(::Deploy::GeneratedAssetCheck)
        result = ::Deploy::GeneratedAssetCheck.run
        outcome = result.respond_to?(:outcome) ? result.outcome : nil
        details = compiled_asset_details(result, outcome)
        if outcome == :passed && result.respond_to?(:conclusive?) && result.conclusive?
          receipt("assessed_clean", evidence: details, counts: { "checks" => result.checks_ran.to_i })
        elsif outcome == :failed
          receipt("violation_found", reason: "generated asset contract failed", evidence: details,
            findings: Array(result.failures).first(30))
        else
          receipt("inconclusive", reason: "generated asset check was not conclusive", evidence: details)
        end
      end

      def compiled_asset_details(result, outcome)
        {
          "checker" => "Deploy::GeneratedAssetCheck",
          "outcome" => outcome.to_s,
          "checked" => result.respond_to?(:checks_ran) ? result.checks_ran.to_i : nil,
          "inconclusive" => result.respond_to?(:unchecked) ? Array(result.unchecked).first(8) : [],
          "failures" => result.respond_to?(:failures) ? Array(result.failures).first(12) : [],
        }.compact
      end

      def ruby_reference_candidates(path, reference)
        base = File.expand_path(reference, File.dirname(path))
        [base, "#{base}.rb", File.join(base, "index.rb")].uniq
      end

      def module_reference_candidates(path, reference)
        base = File.expand_path(reference, File.dirname(path))
        [base, *%w[.js .mjs .cjs .ts .tsx .jsx].map { |extension| "#{base}#{extension}" },
         *%w[index.js index.mjs index.ts index.tsx].map { |name| File.join(base, name) }].uniq
      end
    end
  end
end
