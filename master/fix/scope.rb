# frozen_string_literal: true

module Fix
  # What one proposal may take on and touch.
  #
  # One scope window a proposal (pub4 36bb17ca45): a file's findings are
  # clustered in line order into windows of WINDOW lines and a proposal takes
  # the fullest, so a 2,800-line stylesheet is no longer one proposal for five
  # Laws from line 1 to line 1956. A whole-file finding (every finding of its
  # Law on line 1) goes alone, after the windows. The rest wait for the next
  # pass, which rescans the repaired file.
  #
  # The lines it may change, said in the prompt (pub4 30aaecd1c8): the same
  # PAD range the scope check enforces, its call-site exception, and the
  # guards the changed lines must keep.
  module Scope
    PAD = 25
    WINDOW = PAD * 2
    CALL_SITE_HUNK_MAX = 4
    GUARD_NOTE = "Keep every guard the changed lines hold: each if/unless condition, nil check " \
                 "(`x &&`, `&.`), early return and rescue stays, or the change is refused as unsafe."
    GUARDS = { "if/unless" => /\b(if|unless)\b/, "nil check" => /&&|&\./, "early return" => /\breturn\b/,
               "rescue" => /\brescue\b/ }.freeze

    Hunk = Data.define(:old_from, :old_to, :removed, :added) do
      def size = [removed.size, added.size].max
      def text = (removed + added).join
    end

    module_function

    # [taken, deferred]
    def narrow(findings, window: WINDOW)
      taken = groups(findings, window:).first || []
      [taken, findings - taken]
    end

    def groups(findings, window: WINDOW)
      whole, located = findings.partition { |finding| whole_file?(finding, findings) }
      windows = clusters(located.sort_by(&:line), window)
      ranked = windows.each_with_index.sort_by { |group, index| [-group.size, index] }.map(&:first)
      ranked + whole.group_by { |finding| finding.law.to_s }.values
    end

    def clusters(sorted, window)
      sorted.each_with_object([]) do |finding, out|
        start = out.last&.first
        start && finding.line - start.line <= window ? out.last << finding : out << [finding]
      end
    end

    def whole_file?(finding, findings)
      findings.select { |other| other.law == finding.law }.all? { |other| other.line <= 1 }
    end

    def range(findings)
      lines = findings.map(&:line).select(&:positive?)
      return if lines.empty? || findings.all? { |f| whole_file?(f, findings) }

      [lines.min - PAD, 1].max..(lines.max + PAD)
    end

    def note(findings)
      range = range(findings) or return GUARD_NOTE
      "Every changed line must lie between line #{range.begin} and line #{range.end} of the file; a change " \
        "outside that range is refused, except a short edit at a call of a method defined inside it.\n#{GUARD_NOTE}"
    end

    # nil when every hunk lies in range or is a short edit at a call of a
    # method defined in range; else a sentence saying where.
    def outside(findings, old_text, new_text)
      range = range(findings) or return
      old_lines = old_text.lines
      callees = old_lines[(range.begin - 1)..(range.end - 1)].to_a
                .filter_map { |line| line[/\bdef\s+(?:self\.)?([a-z_]\w*[?!=]?)/, 1] }
                .reject { |name| name.size < 4 || %w[call initialize].include?(name) }.uniq
      stray = hunks(old_lines, new_text.lines).reject { |hunk| in_scope?(hunk, range, callees) }
      return if stray.empty?

      "changes lines #{stray.map(&:old_from).min}-#{stray.map(&:old_to).max}, finding range is #{range.begin}-#{range.end}"
    end

    def in_scope?(hunk, range, callees)
      return true if range.cover?(hunk.old_from) && range.cover?(hunk.old_to)
      return false if hunk.size > CALL_SITE_HUNK_MAX

      callees.any? { |name| hunk.text.match?(/(?<![\w@$])#{Regexp.escape(name)}(?!\w)/) }
    end

    # The guard a change drops, or nil: a kind the old lines of a hunk hold
    # more often than its new lines.
    def dropped_guard(old_text, new_text)
      hunks(old_text.lines, new_text.lines).each do |hunk|
        GUARDS.each do |name, pattern|
          before = hunk.removed.sum { |line| line.scan(pattern).size }
          after = hunk.added.sum { |line| line.scan(pattern).size }
          return "drops a #{name} near line #{hunk.old_from}" if after < before
        end
      end
      nil
    end

    # Line hunks between two texts: the common head and tail trimmed, the
    # middle split by an LCS when it is small enough, else one hunk.
    def hunks(old_lines, new_lines)
      head = 0
      head += 1 while head < old_lines.size && head < new_lines.size && old_lines[head] == new_lines[head]
      tail = 0
      tail += 1 while tail < old_lines.size - head && tail < new_lines.size - head &&
                      old_lines[-1 - tail] == new_lines[-1 - tail]
      old_mid = old_lines[head...(old_lines.size - tail)]
      new_mid = new_lines[head...(new_lines.size - tail)]
      return [] if old_mid.empty? && new_mid.empty?
      return [hunk_at(head, old_mid, new_mid)] if old_mid.size * new_mid.size > 4_000_000

      lcs_hunks(old_mid, new_mid, head)
    end

    def hunk_at(offset, removed, added)
      from = offset + 1
      Hunk.new(old_from: from, old_to: [from + removed.size - 1, from].max, removed:, added:)
    end

    def lcs_hunks(old_mid, new_mid, offset)
      table = Array.new(old_mid.size + 1) { Array.new(new_mid.size + 1, 0) }
      old_mid.size.downto(1) do |i|
        new_mid.size.downto(1) do |j|
          table[i - 1][j - 1] = old_mid[i - 1] == new_mid[j - 1] ? table[i][j] + 1 : [table[i][j - 1], table[i - 1][j]].max
        end
      end
      walk(table, old_mid, new_mid, offset)
    end

    def walk(table, old_mid, new_mid, offset)
      out = []
      i = j = 0
      pending = nil
      while i < old_mid.size || j < new_mid.size
        if i < old_mid.size && j < new_mid.size && old_mid[i] == new_mid[j]
          out << hunk_at(offset + pending[0], pending[1], pending[2]) if pending
          pending = nil
          i += 1
          j += 1
          next
        end
        pending ||= [i, [], []]
        if j < new_mid.size && (i >= old_mid.size || table[i][j + 1] >= table[i + 1][j])
          pending[2] << new_mid[j]
          j += 1
        else
          pending[1] << old_mid[i]
          i += 1
        end
      end
      out << hunk_at(offset + pending[0], pending[1], pending[2]) if pending
      out
    end
  end
end
