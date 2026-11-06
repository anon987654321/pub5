# frozen_string_literal: true

require "io/console"

module Cli
  # What reaches the terminal. Status lines are dmesg-style, `unit0: fact`,
  # outcome first, one line, ASCII punctuation (operator decision 2026-11-06:
  # typographic marks belong to web copy, ASCII to the terminal), no colour
  # and no control sequences, so NO_COLOR, a dumb terminal and a pipe all
  # read the same bytes. Secrets never reach either stream.
  module Terminal
    ASCII = {
      "…" => "...", "–" => "-", "—" => "-", "‘" => "'", "’" => "'",
      "“" => '"', "”" => '"', "«" => '"', "»" => '"', "→" => "->",
      "←" => "<-", "•" => "-", " " => " ", "−" => "-"
    }.freeze
    ASCII_RE = Regexp.union(ASCII.keys)
    # A model reply or a lane's complaint can quote a key; it is shown as the
    # kind of secret, never its value.
    SECRET = /\b(?:sk-(?:ant-)?[A-Za-z0-9_-]{16,}|xai-[A-Za-z0-9]{16,}|gsk_[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,})\b|(?<=Bearer )\S+/
    WIDTH = 100

    module_function

    # Typographic punctuation to ASCII; letters (Norwegian included) stay.
    def ascii(text) = text.to_s.gsub(ASCII_RE, ASCII)

    def redact(text) = text.to_s.gsub(SECRET, "[secret]")

    def clean(text) = redact(ascii(text))

    # One status line: `unit0: message`, outcome first. On a terminal it wraps
    # at the width under its prefix, so neither the outcome nor the recovery
    # action at the end is cut away; in a pipe or a log (width nil) it is one
    # line, whole.
    def line(unit, message, width: nil)
      prefix = "#{unit}0: "
      text = "#{prefix}#{clean(message).gsub(/\s*\n\s*/, '; ').strip}"
      return text if width.nil? || text.size <= width

      wrap(text, width, " " * prefix.size)
    end

    def wrap(text, width, indent)
      rows = [+""]
      text.split(" ").each do |word|
        row = rows.last
        if !row.strip.empty? && row.size + 1 + word.size > width
          rows << "#{indent}#{word}"
        else
          row << (row.empty? || row == indent ? "" : " ") << word
        end
      end
      rows.join("\n")
    end

    def width(io)
      # A pty that reports 0 columns (script(1), some CI) has no width.
      cols = io.respond_to?(:winsize) && io.tty? ? io.winsize.last : 0
      cols.positive? ? cols.clamp(40, 400) : nil
    rescue IOError, SystemCallError
      WIDTH
    end

    # Elapsed seconds as measured, with spend when the ledger has one.
    def spend(reply)
      cost = reply.cost_usd ? format(", $%.4f", reply.cost_usd) : ""
      "#{reply.tokens_in.to_i} in #{reply.tokens_out.to_i} out#{cost}"
    end
  end
end
