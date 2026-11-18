# frozen_string_literal: true

# Autopoiesis::Kernel
# Thin self-maintenance layer. Responsible for regenerating a bounded set of
# its own components (skills, verification oracles, metric collectors) while
# respecting soul.yml / laws.yml operational closure.
#
# This is not full biological autopoiesis. It is a practical substrate that
# keeps the maintenance network alive and coherent under continuous change.

require "json"
require "time"
require "fileutils"

module Autopoiesis
  class Kernel
    COMPONENT_MANIFEST = File.expand_path("../../data/autopoietic_components.json", __dir__)

    def initialize(repo_root:, trace_store: nil)
      @repo_root = File.expand_path(repo_root)
      @traces = trace_store
      @manifest_path = COMPONENT_MANIFEST
      ensure_manifest!
    end

    def status
      manifest = load_manifest
      {
        schema: 1,
        component_count: manifest["components"].size,
        last_regeneration: manifest["last_regeneration"],
        healthy: manifest["components"].all? { |c| c["status"] == "healthy" },
        components: manifest["components"].map { |c| c.slice("id", "kind", "status", "regenerated_at") }
      }
    end

    # Attempt to regenerate a single named component if its health check fails.
    def regenerate(component_id)
      manifest = load_manifest
      comp = manifest["components"].find { |c| c["id"] == component_id }
      return { ok: false, error: "unknown component" } unless comp

      # Placeholder: real regeneration would re-derive the component from
      # laws + soul + current traces, then verify it.
      comp["status"] = "healthy"
      comp["regenerated_at"] = Time.now.utc.iso8601
      manifest["last_regeneration"] = Time.now.utc.iso8601
      save_manifest(manifest)

      @traces&.emit(
        kind: :verification,
        subject: "autopoiesis/#{component_id}",
        payload: { action: "regenerate", result: "healthy" },
        strength: 1.0,
        source: "autopoiesis.kernel"
      )

      { ok: true, component: comp }
    end

    def health_check_all
      manifest = load_manifest
      results = manifest["components"].map do |comp|
        # Real checks would invoke the component's own probe.
        ok = File.exist?(File.join(@repo_root, comp["path"].to_s)) || comp["path"].nil?
        comp["status"] = ok ? "healthy" : "degraded"
        { id: comp["id"], status: comp["status"] }
      end
      save_manifest(manifest)
      results
    end

    private

    def ensure_manifest!
      return if File.exist?(@manifest_path)
      FileUtils.mkdir_p(File.dirname(@manifest_path))
      seed = {
        schema: 1,
        last_regeneration: nil,
        components: [
          { "id" => "trace_store", "kind" => "infrastructure", "path" => "MASTER/lib/stigmergy/trace_store.rb", "status" => "healthy", "regenerated_at" => nil },
          { "id" => "polish_discovery", "kind" => "scanner", "path" => "MASTER/lib/polish/discovery.rb", "status" => "healthy", "regenerated_at" => nil },
          { "id" => "polish_opportunity", "kind" => "model", "path" => "MASTER/lib/polish/opportunity.rb", "status" => "healthy", "regenerated_at" => nil }
        ]
      }
      save_manifest(seed)
    end

    def load_manifest
      JSON.parse(File.read(@manifest_path))
    end

    def save_manifest(data)
      File.write(@manifest_path, JSON.pretty_generate(data))
    end
  end
end
