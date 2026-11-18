# frozen_string_literal: true

# Polish::Opportunity
# A single, actionable polishing item that MASTER can discover, prioritise,
# and (when safe) implement under /fix.
#
# Opportunities are never TODOs. They assume the backlog is empty and the
# system is in continuous refinement mode.

require "json"
require "securerandom"
require "time"

module Polish
  class Opportunity
    CATEGORIES = %w[
      structure naming documentation typography accessibility
      ui ux cli interaction resilience provenance performance
      consistency stigmergy autopoiesis principle testability
      operator meta
    ].freeze

    SEVERITIES = %w[cosmetic minor moderate substantial].freeze

    attr_reader :id, :category, :severity, :title, :rationale,
                :surface, :evidence, :suggested_action, :created_at,
                :status, :trace_id

    def initialize(
      category:,
      title:,
      rationale:,
      surface:,
      severity: "minor",
      evidence: {},
      suggested_action: nil,
      trace_id: nil,
      id: nil,
      status: "open"
    )
      @id = id || SecureRandom.uuid
      @category = category.to_s
      @severity = severity.to_s
      @title = title.to_s
      @rationale = rationale.to_s
      @surface = surface.to_s
      @evidence = evidence
      @suggested_action = suggested_action
      @trace_id = trace_id
      @created_at = Time.now.utc.iso8601
      @status = status
      freeze
    end

    def to_h
      {
        id: id,
        category: category,
        severity: severity,
        title: title,
        rationale: rationale,
        surface: surface,
        evidence: evidence,
        suggested_action: suggested_action,
        trace_id: trace_id,
        created_at: created_at,
        status: status
      }
    end

    def to_json(*_args)
      JSON.pretty_generate(to_h)
    end

    def self.from_h(h)
      new(
        id: h[:id] || h["id"],
        category: h[:category] || h["category"],
        severity: h[:severity] || h["severity"],
        title: h[:title] || h["title"],
        rationale: h[:rationale] || h["rationale"],
        surface: h[:surface] || h["surface"],
        evidence: h[:evidence] || h["evidence"] || {},
        suggested_action: h[:suggested_action] || h["suggested_action"],
        trace_id: h[:trace_id] || h["trace_id"],
        status: h[:status] || h["status"] || "open"
      )
    end
  end
end
