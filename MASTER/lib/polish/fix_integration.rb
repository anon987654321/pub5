# frozen_string_literal: true

# Polish::FixIntegration
# Hooks polishing discovery into the existing /fix pipeline.
# When /fix runs (or MASTER_BACKLOG_AUTORUN / continuous mode), this module
# can surface and optionally apply safe polishing opportunities.
#
# Contract:
# - Never invents product features.
# - Never creates new .md documents (policy in data/polish_policy.yml).
# - Only proposes or applies changes that improve structure, consistency,
#   existing documentation, accessibility, principle adherence, or operator experience.
# - Every applied change must leave a TraceStore record and a verification receipt.

require_relative "discovery"
require_relative "opportunity"
require_relative "../stigmergy/trace_store"
require_relative "../autopoiesis/kernel"

module Polish
  class FixIntegration
    def initialize(repo_root:)
      @repo_root = File.expand_path(repo_root)
      @traces = Stigmergy::TraceStore.new
      @discovery = Discovery.new(repo_root: @repo_root, trace_store: @traces)
      @auto = Autopoiesis::Kernel.new(repo_root: @repo_root, trace_store: @traces)
    end

    # Entry point for /fix polish phase.
    # mode: :discover | :discover_and_emit | :apply_safe
    def run(mode: :discover_and_emit, limit: 50, surfaces: :all)
      case mode
      when :discover
        @discovery.scan(surfaces: surfaces, limit: limit)
      when :discover_and_emit
        @discovery.scan_and_emit!(surfaces: surfaces, limit: limit)
      when :apply_safe
        apply_safe_batch(limit: limit, surfaces: surfaces)
      else
        raise ArgumentError, "unknown mode: #{mode}"
      end
    end

    def health
      {
        traces_active: @traces.read_active.size,
        autopoiesis: @auto.status,
        discovery_ready: true
      }
    end

    private

    def apply_safe_batch(limit:, surfaces:)
      opps = @discovery.scan(surfaces: surfaces, limit: limit)
      applied = []
      opps.each do |opp|
        next unless safe_to_auto_apply?(opp)
        result = apply_one(opp)
        applied << result if result[:ok]
      end
      applied
    end

    def safe_to_auto_apply?(opp)
      # Only the most mechanical, reversible categories are auto-applicable.
      %w[documentation naming structure].include?(opp.category) &&
        %w[cosmetic minor].include?(opp.severity)
    end

    def apply_one(opp)
      # Real application would dispatch to specialised fixers.
      # For now we only emit the intent and mark the opportunity.
      @traces.emit(
        kind: :polish,
        subject: opp.surface,
        payload: { action: "apply_intent", opportunity: opp.to_h },
        strength: 1.5,
        source: "polish.fix_integration"
      )
      { ok: true, id: opp.id, surface: opp.surface, note: "intent recorded; specialised fixers not yet wired" }
    end
  end
end
