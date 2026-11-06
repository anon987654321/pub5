# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/typesetting.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a0c01ed1f03c94f2
require_relative "../lib/master"

# law/typesetting.rb - the web-copy typesetting Laws (Bringhurst, Butterick, Strunk), one Law.define
# per law.
#
# Their subject is the copy a reader meets on a page: locale values, the text between ERB tags,
# and the Markdown under a docs/ directory. Terminal output is exempt from every one of them -
# the CLI, the REPL, the face and dmesg stay ASCII (operator, 2026-11-06) - and so is anything
# that is not copy: YAML keys and quoting, tag attributes, code spans and fences. The glyphs
# the fixes name are built from code points, so this file stays ASCII.
require_relative "../checks/support/rendered_design"

module Law
  module Typesetting
    # MASTER/docs is read by agents in a terminal as often as by people in a browser, so it
    # keeps its ASCII too (2026-11-06; reversible here).
    TERMINAL_OUTPUT = %r{MASTER/(?:lib/(?:cli|voice/renderer|trace)|bin|docs)/|face_ascii|dmesg}
    PATH = %r{(?:/config/locales/[^/]+\.yml|\.html\.erb|/docs/[^/]+\.md)\z}
    POINTS = { laquo: 0xAB, raquo: 0xBB, ndash: 0x2013, mdash: 0x2014, nbsp: 0xA0, times: 0xD7, degree: 0xB0 }.freeze
    MARKS = POINTS.transform_values { |point| [point].pack("U") }.freeze
    KEY_LINE = /\A(?<indent>\s*)(?:-\s+)?(?<key>[\w.-]+|"[^"]+"|'[^']+'):(?:\s+(?<value>.*))?\z/

    CHROME_KEYS = %w[nav buttons actions empty flash notices errors auth search onboarding].freeze
    SKIP_BLOCK = %r{<(script|style|pre|code)\b}i
    BLOCK_SCALAR = /\A[|>][-+]?\s*\z/
    READERS = { /\.yml\z/ => :locale_values, /\.erb\z/ => :erb_text, /\.md\z/ => :markdown_text }.freeze
    QUOTES = { "'" => ["''", "'"], '"' => ['\\"', '"'] }.freeze

    module_function

    def mark(name) = MARKS.fetch(name)

    def locale(path) = File.basename(path.to_s)[/\A(nb|nn|no|en)\b/, 1]&.then { |code| code == "en" ? "en" : "nb" }

    def unquote(raw)
      text = raw.to_s.strip
      escaped, plain = QUOTES[text[0]]
      return text.sub(/\s+#.*\z/, "") unless escaped && text.size > 1 && text.end_with?(text[0])

      text[1..-2].gsub(escaped, plain)
    end

    # Each copy text with its line number and (for locale files) its key path.
    def each_text(src, path, &block)
      return enum_for(:each_text, src, path) unless block
      return if path.to_s.match?(TERMINAL_OUTPUT)

      reader = READERS.find { |pattern, _reader| path.to_s.match?(pattern) }&.last
      send(reader, src, &block) if reader
    end

    # A locale file read line by line, keeping the key path and block scalars.
    class LocaleWalk
      def initialize
        @stack = []
        @scalar = nil
      end

      def keys = @stack.map(&:last)

      # Yields the copy one line carries, if it carries any.
      def read(line)
        indent = line[/\A */].size
        if inside?(line, indent)
          yield line.strip
          return
        end

        @scalar = nil
        match = KEY_LINE.match(line.chomp) or return
        push(indent, match[:key])
        value = match[:value].to_s
        @scalar = indent if value.match?(BLOCK_SCALAR)
        yield Typesetting.unquote(value) unless @scalar || value.strip.empty?
        nil
      end

      private

      def inside?(line, indent) = @scalar && (line.strip.empty? || indent > @scalar)

      def push(indent, key)
        @stack.pop while @stack.any? && @stack.last.first >= indent
        @stack << [indent, key.delete("\"'")]
      end
    end

    def locale_values(src)
      walk = LocaleWalk.new
      src.each_line.with_index(1) { |line, number| walk.read(line) { |text| yield text, number, walk.keys } }
    end

    def visible_text(line) = line.gsub(/<%.*?%>/m, "X").gsub(/<!--.*?-->/, " ").gsub(/<[^>]*>?/, " ").strip

    def erb_text(src)
      inside = nil
      src.each_line.with_index(1) do |line, number|
        inside = nil if inside && line.match?(%r{</#{inside}>}i)
        next if inside || line.match?(/\A\s*[\w:@.-]+=["']/)

        opened = line[SKIP_BLOCK, 1]
        inside = opened if opened && !line.match?(%r{</#{opened}>}i)
        text = visible_text(line)
        yield text, number, [] unless text.empty?
      end
    end

    def markdown_text(src)
      fenced = false
      src.each_line.with_index(1) do |line, number|
        fenced = !fenced if line.match?(/\A\s*(?:```|~~~)/)
        next if fenced || line.match?(/\A\s*\|/) || line.start_with?("    ")

        text = line.gsub(/`[^`]*`/, " X ").strip
        yield text, number, [] unless text.empty?
      end
    end

    # Findings for one Law: the block answers a message for a text, or nil.
    def judge(src, path, scope = nil)
      each_text(src, path).filter_map do |text, number, keys|
        next if scope && !scope.call(keys)

        message = yield(text, locale(path) || "nb", keys)
        { line: number, message: } if message
      end
    end

    def quotes(text, lang)
      pair = lang == "en" ? "U+201C..U+201D" : "U+00AB..U+00BB"
      return "straight quotes around copy - use #{pair}" if text.match?(/"[^"\n]{1,80}"/)

      "straight apostrophe in copy - use U+2019" if text.match?(/\p{L}'\p{L}/)
    end

    def dash(text, lang)
      return "hyphen as a dash - set a spaced en dash (U+2013)" if text.match?(/\p{L} -{1,2} \p{L}|\p{L}--\p{L}/)

      close = lang == "nb" && text.match?(/\p{L}#{mark(:mdash)}\p{L}/)
      "close-set em dash in nb copy - Norwegian sets it spaced, en dash" if close
    end

    SYMBOLS = {
      /\d\s?x\s?\d+(?:[.,]\d+)?\s?(?:cm|mm|m|px)\b/ => "x in a dimension - write U+00D7",
      /\((?:c|tm|r)\)/i => "(c), (tm) or (r) - write the true mark",
      /(?:\A|\s)-\d[\d,. ]*\s?(?:kr|%|#{MARKS.fetch(:degree)})/ => "hyphen before a value - write U+2212",
    }.freeze

    def symbol(text) = SYMBOLS.find { |pattern, _message| text.match?(pattern) }&.last

    UNIT = /(?:\d|%\{\w+\}|\bX) (?:kr|NOK|km|min|kg|stk|%)(?!\p{L})|\d \d{3}(?!\d)|\bkl\. \d/

    def unit_breaks(src, path)
      breaks = judge(src, path) do |text, _lang|
        "a plain space breaks #{text[UNIT].inspect} - use U+00A0" if text.match?(UNIT)
      end
      delims = src.each_line.with_index(1).filter_map do |line, number|
        { line: number, message: "delimiter is a plain space - use U+00A0" } if line.match?(/delimiter:\s*["'] ["']/)
      end
      (breaks + delims).uniq { |hit| hit[:line] }
    end

    def locale_fixture(key, value)
      group, name = key.split(".")
      "nb:\n  #{group}:\n    #{name}: \"#{value}\"\n"
    end
  end

  C = Typesetting

  










  










  










  














  
















  















end
