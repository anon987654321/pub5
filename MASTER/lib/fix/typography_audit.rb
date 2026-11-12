# frozen_string_literal: true

module Master
  module Fix
    # The style stage of the /fix pass — the typographic law's audit half.
    #
    # laws.yml#typography sets the marks; Renderer#beautify sets them on the
    # way out; this audit reads the operator-facing strings that produce the
    # rest. It scans the trees that speak to a person (cli, voice, trace) for
    # the mechanical lapses: a typographic mark in terminal output, which is
    # ASCII (operator, 2026-11-06: a dash is "-", an ellipsis "..."), and the
    # double-hyphen dash that stands in for a single hyphen in prose. Flags
    # ("--dry-run"), globs and paths are exempt by shape, so a finding is a
    # sentence that reached a person wearing the wrong mark.
    class TypographyAudit
      SCOPE = %w[lib/cli lib/voice lib/trace lib/fix].freeze
      PUNCTUATION_SCOPE = %w[lib/cli lib/voice lib/trace].freeze
      TERMINAL_LINE_LIMIT = 72
      OUTPUT_CALL = /(?:\.\s*(?:status|say|emit|puts|print|warn)\b|\b(?:puts|print|warn|say)\b)/.freeze
      # The marks proper typography sets in copy and a terminal does not print.
      TERMINAL_MARK = /[\u2014\u2013\u00B7\u2022\u2026\u201C\u201D\u2018\u2019\u2192\u2190\u00D7\u2265\u2264]/.freeze
      PROSE_DOUBLE_DASH = /(?<=\s)--(?=\s)/.freeze
      STRING_LITERAL = /"([^"\n]{6,300})"/.freeze
      # Where a machine reads the line, the marks stay literal: fixtures that
      # demonstrate the wrong mark, and usage notation ("<path>...") that
      # follows the man-page convention.
      EXEMPT_MARKERS = %w[bad: fixtures example: usage <path>].freeze
      MAX_FINDINGS = 40

      Finding = Data.define(:file, :line, :kind, :snippet)

      attr_reader :root

      def initialize(root:)
        @root = root.to_s
      end

      def call
        findings = SCOPE.flat_map { |dir| audit_dir(File.join(@root, dir)) }
        report(findings)
      rescue StandardError => e
        "style0: audit unavailable, #{e.class}: #{e.message}"
      end

      private

      def audit_dir(dir)
        return [] unless File.directory?(dir)

        Dir.glob(File.join(dir, "**", "*.rb")).sort.flat_map { |file| audit_file(file) }
      end

      # A small source-side sensor, not rendered terminal proof. Remember the
      # emission line across a short multiline call so the message literal is
      # measured even when it sits on the next line.
      def audit_file(file)
        relative = file.delete_prefix("#{@root}/")
        lines = File.readlines(file, chomp: true)
        output_context = {}
        lines.each_with_index do |source_line, index|
          next unless source_line.match?(OUTPUT_CALL)

          (index..[index + 4, lines.size - 1].min).each { |line_index| output_context[line_index] = true }
        end
        lines.each_with_index.filter_map do |line, index|
          next if line.strip.start_with?("#")
          next if EXEMPT_MARKERS.any? { |marker| line.include?(marker) }

          text = line.scan(STRING_LITERAL).map(&:first).join(" ")
          next if text.empty?

          kind = violation_kind(text, line, relative, output_call: output_context[index] == true)
          next unless kind

          Finding.new(file: relative, line: index + 1, kind:, snippet: text[0, 80])
        end
      rescue StandardError
        []
      end

      def violation_kind(text, line, relative, output_call:)
        terminal_copy = PUNCTUATION_SCOPE.any? { |scope| relative.start_with?(scope + "/") } ||
          (relative.start_with?("lib/fix/") && output_call)
        return "non_ascii_punctuation" if terminal_copy && text.match?(TERMINAL_MARK)
        return "prose_double_dash" if terminal_copy && text.match?(PROSE_DOUBLE_DASH)
        return "terminal_measure" if output_call && text.length > TERMINAL_LINE_LIMIT

        nil
      end

      def report(findings)
        return "style0: clean, #{scoped_line}" if findings.empty?

        counted = findings.group_by(&:kind).transform_values(&:size)
          .map { |kind, count| "#{count} #{kind.tr('_', ' ')}" }
          .join(", ")
        head = "style0: #{findings.size} findings, #{counted}"
        listed = findings.first(MAX_FINDINGS).map { |f| "#{f.file}:#{f.line} #{f.kind} - #{f.snippet}" }
        ([head] + listed + (findings.size > MAX_FINDINGS ? ["style0: #{findings.size - MAX_FINDINGS} more"] : [])).join("\n")
      end

      def scoped_line
        SCOPE.join(" ")
      end
    end
  end
end
