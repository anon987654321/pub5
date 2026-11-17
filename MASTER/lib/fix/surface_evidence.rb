# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "set"
require "time"
require "yaml"
require_relative "../io/process_spawn"
require_relative "surface_evidence/receipts"
require_relative "surface_evidence/visual_receipts"
require_relative "surface_evidence/execution_receipts"
require_relative "surface_evidence/inventory"
require_relative "surface_evidence/runtime_probes"
require_relative "surface_evidence/command_execution"

module Master
  module Fix
    # Read-only, target-scoped sensors for surfaces that a source scanner alone
    # cannot prove. These receipts supplement Law findings; they never turn a
    # missing adapter into a clean result, and they never deploy or mutate source.
    # This file holds the orchestration, the capture report and the shared
    # receipt support; the per-surface builders, the inventory, the runtime
    # probes and the command runner live in the surface_evidence/ parts that
    # re-open this class.
    class SurfaceEvidence
      SCHEMA_VERSION = 1
      INVENTORY_CAP = Integer(ENV.fetch("MASTER_FIX_SURFACE_INVENTORY_CAP", "30000"))
      MAX_PROCESS_OUTPUT = 16_384
      DEFAULT_COMMAND_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_COMMAND_TIMEOUT_S", "180"))
      TEST_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_TEST_TIMEOUT_S", "600"))
      RUNTIME_TIMEOUT = Integer(ENV.fetch("MASTER_FIX_SURFACE_RUNTIME_TIMEOUT_S", "180"))
      IGNORED_DIRECTORIES = %w[
        .git .master .bundle node_modules vendor/bundle tmp log storage coverage
        .cache .sass-cache
      ].freeze
      MEDIA_EXTENSIONS = %w[
        .png .jpg .jpeg .gif .webp .avif .svg .ico .bmp .tif .tiff .pdf
        .wav .mp3 .m4a .aac .ogg .flac .mp4 .mov .webm .woff .woff2 .ttf .otf
      ].freeze
      RUNTIME_EXTENSIONS = %w[
        .rb .rake .gemspec .erb .js .mjs .cjs .ts .tsx .jsx
        .sh .bash .ksh .zsh
      ].freeze

      SOURCE_TYPES = %w[file directory symlink other].freeze
      COMPLETE_STATUSES = %w[assessed_clean not_applicable].freeze
      SURFACES = %w[
        repository_tree directories file_names paths cross_file media_assets compiled_assets
        rendered_ui interactive_behavior tests runtime deployment
      ].freeze

      def self.capture(root:, target:, plan:, files:, visual_result: nil, reference_graph: nil,
                       cache: {}, run_expensive: false)
        new(
          root:, target:, plan:, files:, visual_result:, reference_graph:, cache:, run_expensive:,
        ).capture
      end

      def initialize(root:, target:, plan:, files:, visual_result:, reference_graph:, cache:, run_expensive:)
        @root = File.expand_path(root)
        @target = File.expand_path(target.to_s, @root)
        @plan = plan
        @files = Array(files).map { |path| File.expand_path(path.to_s, @root) }.uniq.sort
        @visual_result = visual_result
        @reference_graph = reference_graph
        @cache = cache
        @run_expensive = run_expensive == true
        @target_label = relative(@target)
        @tree = @target_label.split("/", 2).first
      end

      def capture
        source_before = source_manifest
        inventory_before = inventory_snapshot
        @current_inventory_digest = inventory_before["digest"]
        receipts = initial_receipts(inventory_before, source_before)

        source_after = source_manifest
        inventory_after = inventory_snapshot
        stable = surface_stability(source_before, source_after, inventory_before, inventory_after)
        mark_unstable_receipts(receipts, source_after, inventory_after) unless stable

        complete = stable && receipts.values.all? { |receipt| COMPLETE_STATUSES.include?(receipt["status"]) }
        compact = compact_surface_rows(receipts)
        report_digest = surface_report_digest(compact, inventory_before)
        capture_report(receipts, compact, complete, report_digest,
          source_before:, source_after:, inventory_before:, inventory_after:, stable:)
      rescue StandardError => e
        failed_report(e)
      end

      private

      def cached(name)
        key = [name.to_s, @plan&.source_digest.to_s, @plan&.scope_digest.to_s, @current_inventory_digest.to_s]
        return json_safe(@cache[key]) if @cache.key?(key)

        result = yield
        @cache[key] = result if result.is_a?(Hash) && %w[assessed_clean violation_found not_applicable].include?(result["status"].to_s)
        result
      rescue StandardError => e
        receipt("inconclusive", reason: "#{name} probe failed: #{error_text(e)}")
      end

      def initial_receipts(inventory, source)
        receipts = {}
        receipts["repository_tree"] = tree_receipt(inventory, source)
        receipts["directories"] = directory_receipt(inventory, source)
        receipts["file_names"] = file_name_receipt(inventory, source)
        receipts["paths"] = path_receipt(inventory, source)
        receipts["cross_file"] = cross_file_receipt(inventory, source)
        receipts["media_assets"] = media_receipt(inventory, source)
        receipts["compiled_assets"] = compiled_asset_receipt(inventory, source)
        receipts["rendered_ui"] = rendered_ui_receipt
        receipts["interactive_behavior"] = interactive_receipt
        receipts["tests"] = cached("tests") { test_receipt(inventory, source) }
        receipts["runtime"] = cached("runtime") { runtime_receipt(inventory, source) }
        receipts["deployment"] = deployment_receipt(inventory, source)
        receipts
      end

      def surface_stability(source_before, source_after, inventory_before, inventory_after)
        source_before["digest"] == source_after["digest"] &&
          inventory_before["digest"] == inventory_after["digest"] &&
          source_before["status"] == "captured" && source_after["status"] == "captured" &&
          inventory_before["status"] == "captured" && inventory_after["status"] == "captured"
      end

      def mark_unstable_receipts(receipts, source_after, inventory_after)
        reason = "FixPlan source or target inventory changed during surface assessment"
        receipts.each do |name, receipt|
          next if receipt["status"] == "not_applicable"

          receipts[name] = receipt.merge(
            "status" => "inconclusive",
            "reason" => reason,
            "observed_after" => {
              "source_digest" => source_after["digest"],
              "inventory_digest" => inventory_after["digest"],
            },
          )
        end
      end

      def compact_surface_rows(receipts)
        receipts.sort.to_h do |name, receipt|
          [name, {
            "status" => receipt["status"],
            "reason" => receipt["reason"],
            "evidence_sha256" => receipt["evidence_sha256"],
            "counts" => receipt["counts"],
          }.compact]
        end
      end

      def surface_report_digest(compact, inventory)
        Digest::SHA256.hexdigest(JSON.generate(
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "inventory_digest" => inventory["digest"],
          "surface_rows" => compact.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
        ))
      end

      def capture_report(receipts, compact, complete, report_digest,
                         source_before:, source_after:, inventory_before:, inventory_after:, stable:)
        {
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "target_absolute" => @target,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "scope_digest" => @plan&.scope_digest,
          "source_manifest" => capture_source_manifest_section(source_before, source_after, stable),
          "inventory" => capture_inventory_section(inventory_before, inventory_after),
          "surfaces" => compact,
          "details" => receipts,
          "complete" => complete,
          "digest" => report_digest,
        }
      end

      def capture_source_manifest_section(source_before, source_after, stable)
        source_before.merge(
          "verified_after_assessment" => stable,
          "digest_after_assessment" => source_after["digest"],
        )
      end

      def capture_inventory_section(inventory_before, inventory_after)
        {
          "status" => inventory_before["status"],
          "digest" => inventory_before["digest"],
          "files" => inventory_before["files"],
          "directories" => inventory_before["directories"],
          "symlinks" => inventory_before["symlinks"],
          "ignored_directories" => inventory_before["ignored_directories"],
          "truncated" => inventory_before["truncated"],
          "sample" => inventory_before["records"].first(80),
          "after_digest" => inventory_after["digest"],
        }
      end

      def receipt(status, reason: nil, evidence: {}, findings: [], counts: {})
        row = {
          "status" => status.to_s,
          "reason" => reason.to_s.empty? ? nil : safe_text(reason, 240),
          "evidence" => json_safe(evidence),
          "findings" => json_safe(Array(findings).first(30)),
          "counts" => json_safe(counts),
          "evidence_sha256" => digest_json(json_safe(evidence)),
        }
        row.compact
      end

      def captured?(inventory, source)
        inventory["status"] == "captured" && source["status"] == "captured"
      end

      def stat_signature(stat)
        [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r]
      end

      def read_stable(path)
        before = File.stat(path)
        body = File.read(path, encoding: "UTF-8")
        after = File.stat(path)
        return unless stat_signature(before) == stat_signature(after)

        body
      rescue StandardError
        nil
      end

      def relative(path)
        File.expand_path(path.to_s, @root).delete_prefix("#{@root}/")
      end

      def digest_json(value) = Digest::SHA256.hexdigest(JSON.generate(value))

      # Plain JSON values with string keys. Called by the cache and every receipt and never
      # defined, so building any surface receipt raised NoMethodError and the assessment
      # matrix stage failed on every pass.
      def json_safe(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, json_safe(item)] }
        when Array then value.map { |item| json_safe(item) }
        when String, Integer, Float, true, false, nil then value
        else value.to_s
        end
      end

      def safe_text(value, limit = 240)
        value.to_s.gsub(/\s+/, " ").strip[0, limit].to_s
          .gsub(/(?i)(password|passwd|token|secret|authorization)(\s*[:=]\s*)[^\s,;]+/, '\1\2[redacted]')
      end

      def error_text(error) = safe_text("#{error.class}: #{error.message}", 180)

      def row_value(hash, key)
        return unless hash.is_a?(Hash)

        hash[key] || hash[key.to_sym]
      end

      def row_status(hash, key) = row_value(hash, key).to_s

      def result_value(result)
        result.respond_to?(:value!) ? result.value! : nil
      rescue StandardError
        nil
      end

      def failed_report(error)
        reason = "surface evidence failed: #{error_text(error)}"
        rows = SURFACES.to_h { |name| [name, receipt("inconclusive", reason:)] }
        compact = failed_compact_rows(rows)
        {
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "target_absolute" => @target,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "source_manifest" => { "status" => "inconclusive", "reason" => reason },
          "inventory" => { "status" => "inconclusive", "sample" => [] },
          "surfaces" => compact,
          "details" => rows,
          "complete" => false,
          "digest" => failed_report_digest(compact),
        }
      end

      def failed_compact_rows(rows)
        rows.sort.to_h { |name, row| [name, row.slice("status", "reason", "evidence_sha256", "counts").compact] }
      end

      def failed_report_digest(compact)
        digest_json(
          "schema_version" => SCHEMA_VERSION,
          "target" => @target_label,
          "plan_digest" => @plan&.digest,
          "source_digest" => @plan&.source_digest,
          "inventory_digest" => nil,
          "surface_rows" => compact.map { |name, row| [name, row["status"], row["evidence_sha256"]] },
        )
      end

      def rails_target? = @target_label == "RAILS" || @target_label.start_with?("RAILS/") || web_target?

      # MASTER/web is master's Rails app, registered in RAILS/apps.yml like the others.
      def web_target? = @target_label == "MASTER/web" || @target_label.start_with?("MASTER/web/")

      def target_app_name = web_target? ? "master" : @target_label.delete_prefix("RAILS/").split("/", 2).first

      def app_dir(name) = File.join(@root, name == "master" ? "MASTER/web" : "RAILS/#{name}")
    end
  end
end
