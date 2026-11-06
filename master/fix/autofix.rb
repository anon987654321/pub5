# frozen_string_literal: true

module Fix
  # The deterministic repairs that need no model: whitespace a Law already
  # names, rewritten by a transform that can only remove characters. A
  # rewrite is kept only when it clears its Law in that file, raises no other
  # Law's count and still parses; protected files are never written. Kept
  # rewrites are noted in Writes and deliver with the pass.
  module Autofix
    TRANSFORMS = {
      TRAILING_WHITESPACE: ->(text) { text.gsub(/[ \t]+$/, "") },
      CONSECUTIVE_BLANK_LINES: ->(text) { text.gsub(/\n(?:[ \t]*\n){2,}/, "\n\n") },
      BLANK_LINE_RUN: ->(text) { text.gsub(/\n(?:[ \t]*\n){2,}/, "\n\n") },
      FINAL_NEWLINE: ->(text) { text.empty? || text.end_with?("\n") ? text : "#{text}\n" }
    }.freeze

    module_function

    # Rewrites every file whose findings a transform owns; returns the Writes.
    def run(world, findings, laws:, writes: Writes.new)
      owned = findings.select { |f| TRANSFORMS.key?(f.law) && autofix?(laws, f.law) }
      owned.group_by(&:file).each do |path, rows|
        next if world.manifest.protected?(path)

        rewrite(world, path, rows.map(&:law).uniq, laws, writes)
      end
      writes
    end

    def autofix?(laws, id) = laws.find { |law| law.id == id }&.policy&.fetch("autofix", "never") == "automatic"

    def rewrite(world, path, ids, laws, writes)
      before = world.read(path).force_encoding("UTF-8")
      after = ids.reduce(before) { |text, id| TRANSFORMS.fetch(id).call(text) }
      return if after == before || !clean?(path, before, after, ids, laws)

      world.write(path, after)
      writes.note(path, before:, after:, laws: ids)
    end

    def clean?(path, before, after, ids, laws)
      kind = Core::ParseGate.kind(path)
      return false if kind && Core::ParseGate.problem(kind, after)

      counts = ->(text) { laws.flat_map { |law| law.scan(text, path) }.map(&:law).tally }
      was = counts.call(before)
      now = counts.call(after)
      ids.all? { |id| now.fetch(id, 0) < was.fetch(id, 0) } && now.all? { |id, n| n <= was.fetch(id, 0) }
    end
  end
end
