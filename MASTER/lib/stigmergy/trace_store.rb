# frozen_string_literal: true

# Stigmergy::TraceStore
# Append-oriented environmental traces that agents read and write.
# Local patches leave tags; successful paths reinforce signal strength;
# low-signal traces decay. No direct agent-to-agent messaging required.
#
# Authority: subordinate to data/soul.yml and data/laws.yml.
# This module is pure infrastructure; Laws decide what is allowed.

require "json"
require "time"
require "fileutils"
require "securerandom"

module Stigmergy
  class TraceStore
    DEFAULT_PATH = File.expand_path("../../data/traces", __dir__)
    SCHEMA = 1

    attr_reader :root

    def initialize(root: DEFAULT_PATH)
      @root = root
      FileUtils.mkdir_p(@root)
      FileUtils.mkdir_p(File.join(@root, "active"))
      FileUtils.mkdir_p(File.join(@root, "archive"))
    end

    # Record a quality or process signal.
    # kind: :metric | :patch | :tag | :path | :verification | :polish | :decay
    def emit(kind:, subject:, payload: {}, strength: 1.0, source: "unknown", expires_in: nil)
      id = SecureRandom.uuid
      now = Time.now.utc
      record = {
        schema: SCHEMA,
        id: id,
        kind: kind.to_s,
        subject: subject.to_s,
        payload: payload,
        strength: strength.to_f.clamp(0.0, 10.0),
        source: source.to_s,
        created_at: now.iso8601,
        expires_at: expires_in ? (now + expires_in).iso8601 : nil
      }
      path = File.join(@root, "active", "#{now.strftime('%Y%m%dT%H%M%S')}_#{id}.json")
      File.write(path, JSON.pretty_generate(record))
      record
    end

    def read_active(kind: nil, subject_prefix: nil, min_strength: 0.0)
      Dir[File.join(@root, "active", "*.json")].filter_map do |path|
        rec = JSON.parse(File.read(path), symbolize_names: true)
        next if kind && rec[:kind] != kind.to_s
        next if subject_prefix && !rec[:subject].start_with?(subject_prefix.to_s)
        next if rec[:strength].to_f < min_strength
        if rec[:expires_at] && Time.parse(rec[:expires_at]) < Time.now.utc
          archive(path)
          next
        end
        rec.merge(path: path)
      rescue JSON::ParserError
        nil
      end
    end

    def reinforce(id, delta: 0.25)
      path = find_active_path(id)
      return nil unless path
      rec = JSON.parse(File.read(path), symbolize_names: true)
      rec[:strength] = (rec[:strength].to_f + delta).clamp(0.0, 10.0)
      rec[:reinforced_at] = Time.now.utc.iso8601
      File.write(path, JSON.pretty_generate(rec))
      rec
    end

    def decay_all(factor: 0.92, floor: 0.05)
      read_active.each do |rec|
        new_strength = rec[:strength].to_f * factor
        if new_strength < floor
          archive(rec[:path])
        else
          rec[:strength] = new_strength
          rec[:decayed_at] = Time.now.utc.iso8601
          File.write(rec[:path], JSON.pretty_generate(rec.except(:path)))
        end
      end
    end

    def local_patch_tag(subject:, flaw:, fix_summary:, higher_order: nil, source: "agent")
      emit(
        kind: :tag,
        subject: subject,
        payload: {
          flaw: flaw,
          fix_summary: fix_summary,
          higher_order: higher_order,
          cascade_eligible: !higher_order.nil?
        },
        strength: 1.2,
        source: source
      )
    end

    private

    def find_active_path(id)
      Dir[File.join(@root, "active", "*_#{id}.json")].first
    end

    def archive(path)
      return unless path && File.exist?(path)
      dest = File.join(@root, "archive", File.basename(path))
      FileUtils.mv(path, dest)
    end
  end
end
