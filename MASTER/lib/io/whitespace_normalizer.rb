# frozen_string_literal: true

require "prism"
require "yaml"
require "json"
require "set"

module Master
  module Io
    # Shared, content-preserving formatter for writes and /fix.
    module WhitespaceNormalizer
      module_function

      COLLAPSE_INTERNAL_EXTS = %w[.rb].freeze

      DECORATION = /[-=*_~─━═+#.]{3,}/
      HEADER_COMMENT = {
        ".sh" => "#", ".zsh" => "#", ".bash" => "#", ".ksh" => "#",
        ".toml" => "#", ".sql" => "--",
        ".js" => "//", ".mjs" => "//", ".cjs" => "//",
        ".ts" => "//", ".jsx" => "//", ".tsx" => "//",
        ".css" => "/*", ".scss" => "/*",
      }.freeze
      SAFE_EXTENSIONS = %w[.rb .yml .yaml .json .md].freeze


      def normalize(content, path: nil)
        return content unless content.is_a?(String) && !content.empty?

        out = remove_comment_separators(content, path:)
        out = strip_trailing(out, path:)
        out = collapse_blanks(out, path:)
        out = guarded(out, path:) { collapse_internal(out) } if collapse_internal?(path)
        out
      end

      def extension(path)
        return ".rb" if %w[Gemfile Rakefile].include?(File.basename(path.to_s))

        ext = File.extname(path.to_s).downcase
        %w[.rake .gemspec].include?(ext) ? ".rb" : ext
      end

      def guarded(src, path:)
        candidate = yield
        return src if candidate == src
        return src if path && !SAFE_EXTENSIONS.include?(extension(path))
        return src if extension(path) == ".md" && markdown_literal_content?(src)

        case extension(path)
        when ".rb"
          before = Prism.parse(src)
          after = Prism.parse(candidate)
          return src unless before.success? && after.success? && before.value === after.value
          return src unless before.data_loc&.slice == after.data_loc&.slice
          return src unless magic_comments(before) == magic_comments(after)
          return src unless before.encoding == after.encoding
          return src if src.include?("__LINE__") && src.lines.size != candidate.lines.size
        when ".yml", ".yaml"
          return src unless data_equivalent?(src, candidate, path:)
        when ".json"
          return src unless data_equivalent?(src, candidate, path:)
        end
        candidate
      rescue Psych::Exception, JSON::ParserError
        src
      end

      def data_equivalent?(before, after, path:)
        case extension(path)
        when ".yml", ".yaml"
          Psych.parse_stream(before).yaml == Psych.parse_stream(after).yaml
        when ".json"
          json_tokens(before) == json_tokens(after)
        else
          false
        end
      rescue Psych::Exception, JSON::ParserError
        false
      end

      def magic_comments(parsed)
        parsed.magic_comments.map { |comment| [comment.key, comment.value] }
      end

      # Keep duplicate keys, number spellings, order and string escapes intact.
      def json_tokens(src)
        JSON.parse(src)
        src.gsub(/"(?:\\.|[^"\\])*"|[ \t\r\n]+/m) { |token| token.start_with?('"') ? token : "" }
      end

      # A Markdown code block, literal HTML or tab-indented block may contain
      # significant whitespace. Leave these documents to a format-aware review.
      def markdown_literal_content?(src)
        src.match?(/^\s*(?:\x60{3,}|~{3,}|<pre\b|<script\b|<style\b)/i) ||
          src.match?(/^\s*(?:>\s*|[-+*]\s+|\d+[.)]\s+)+(?:\x60{3,}|~{3,})/) ||
          src.match?(/^(?: {4}|\t)/)
      end

      def supported?(path)
        SAFE_EXTENSIONS.include?(extension(path)) || HEADER_COMMENT.key?(extension(path))
      end

      def remove_comment_separators(src, path:)
        return src unless src.match?(DECORATION)

        marker = HEADER_COMMENT[extension(path)]
        return clean_header(src, marker) if marker

        lines = src.lines
        case extension(path)
        when ".rb"
          parsed = Prism.parse(src)
          return src unless parsed.success?
          indexes = parsed.comments.map { |comment| comment.location.start_line - 1 }
        when ".yml", ".yaml"
          protected = yaml_literal_lines(src)
          indexes = (0...lines.size).reject { |index| protected.include?(index) }
        else
          return src
        end

        indexes.each { |index| lines[index] = clean_comment(lines[index], "#") }
        guarded(src, path:) { lines.join }
      rescue Psych::Exception
        src
      end

      # Only the initial comment preamble is unambiguous without a lexer.
      # Never enter program text, multiline strings, heredocs or block comments.
      def clean_header(src, marker)
        in_header = true
        src.each_line.map do |line|
          next line unless in_header
          next line if line.strip.empty? || line.start_with?("#!")

          if standalone_comment?(line, marker)
            clean_comment(line, marker)
          else
            in_header = false
            line
          end
        end.join
      end

      def standalone_comment?(line, marker)
        text = line.lstrip
        return text.match?(%r{\A/\*(?:(?!\*/).)*\*/[ \t]*\r?\n?\z}) if marker == "/*"

        text.start_with?(marker)
      end

      def clean_comment(line, marker)
        return line unless line
        newline = line[/\r?\n\z/] || ""
        text = line.delete_suffix(newline)
        indent = text[/\A[ \t]*/]
        comment = text.delete_prefix(indent)
        return line unless comment.start_with?(marker)
        body = comment.delete_prefix(marker)
        if marker == "/*"
          return line unless body.rstrip.end_with?("*/")
          body = body.rstrip.delete_suffix("*/")
        end
        body = body.strip
        return newline if body.match?(/\A#{DECORATION}\z/)

        title = body.sub(/\A#{DECORATION}[ \t]+/, "").sub(/[ \t]+#{DECORATION}\z/, "")
        return line if title == body || !title.match?(/\A[[:alpha:]][[:alnum:] .,&()\/-]*\z/)

        ending = marker == "/*" ? " */" : ""
        "#{indent}#{marker} #{title}#{ending}#{newline}"
      end

      def collapse_internal?(path)
        return false unless path

        COLLAPSE_INTERNAL_EXTS.include?(extension(path))
      end

      # Parser-protected lines keep multiline literals and block scalars
      # intact while cleanup continues on the rest of the file.
      def yaml_literal_lines(src)
        protected = Set.new
        pending = [Psych.parse_stream(src)]
        until pending.empty?
          node = pending.pop
          if node.is_a?(Psych::Nodes::Scalar) && node.start_line < node.end_line
            finish = node.end_line - (node.end_column.zero? ? 1 : 0)
            protected.merge(node.start_line..finish)
          end
          pending.concat(node.children || [])
        end
        protected
      end

      def ruby_literal_lines(src)
        lexed = Prism.lex(src)
        return Set.new unless lexed.success?

        lexed.value.each_with_object(Set.new) do |(token, _state), protected|
          next unless %i[STRING_CONTENT HEREDOC_END EMBDOC_LINE EMBDOC_BEGIN EMBDOC_END].include?(token.type)

          loc = token.location
          next if token.type == :STRING_CONTENT && loc.start_line == loc.end_line

          finish = loc.end_line - (loc.end_column.zero? ? 1 : 0)
          protected.merge((loc.start_line - 1)..(finish - 1))
        end
      end

      def protected_lines(src, path:)
        case extension(path)
        when ".rb" then ruby_literal_lines(src)
        when ".yml", ".yaml" then yaml_literal_lines(src)
        else Set.new
        end
      end

      def clean_lines(src, path:)
        protected = protected_lines(src, path:)
        src.each_line.with_index.map do |line, index|
          yield(line, protected.include?(index))
        end.join
      rescue Psych::Exception
        src
      end

      def strip_trailing(src, path: nil)
        guarded(src, path:) do
          if extension(path) == ".md"
            src.gsub(/^[ \t]+$/, "").gsub(/(?<=[^ \t\n])[ \t](?=\n|\z)/, "")
          else
            clean_lines(src, path:) do |line, protected|
              protected ? line : line.gsub(/[ \t]+(?=\r?\n|\z)/, "")
            end
          end
        end
      end

      def collapse_blanks(src, path: nil)
        return src unless src.match?(/(?:\r?\n){3,}/)

        guarded(src, path:) do
          previous_blank = false
          clean_lines(src, path:) do |line, protected|
            blank = line.match?(/\A\r?\n\z/)
            omit = blank && previous_blank && !protected
            previous_blank = blank && !protected
            omit ? "" : line
          end
        end
      end

      def expand_tabs(src, path:)
        return src unless src.include?("\t")

        guarded(src, path:) do
          clean_lines(src, path:) { |line, protected| protected ? line : line.gsub("\t", "  ") }
        end
      end

      def ensure_final_newline(src, path:)
        return src if src.empty? || src.end_with?("\n")

        guarded(src, path:) { src + "\n" }
      end

      def collapse_internal(src)
        terminators = []
        src.each_line.map do |line|
          if terminators.any?
            terminators.shift if line.match?(/\A\s*#{Regexp.escape(terminators.first)}\s*$/)
            next line
          end
          if (m = line.match(/<<[-~]?["']?([A-Z_][A-Z0-9_]*)["']?/))
            terminators << m[1]
            next line
          end
          collapse_line(line)
        end.join
      end

      def collapse_line(line)
        leading = line[/\A[ \t]*/]
        rest = line[leading.length..] || ""
        out = +""
        i = 0
        in_str = nil
        while i < rest.length
          i, in_str = collapse_char(rest, i, in_str, out)
        end
        leading + out
      end

      def collapse_char(rest, i, in_str, out)
        c = rest[i]
        return collapse_in_string_char(rest, i, out, in_str) if in_str

        if c == "#"
          out << rest[i..]
          return [rest.length, nil]
        end
        return collapse_spaces(rest, i, out) if c == " " && rest[i + 1] == " "

        out << c
        in_str = c if c == '"' || c == "'"
        [i + 1, in_str]
      end

      def collapse_in_string_char(rest, i, out, in_str)
        c = rest[i]
        out << c
        if c == "\\" && rest[i + 1]
          out << rest[i + 1]
          return [i + 2, in_str]
        end

        in_str = nil if c == in_str
        [i + 1, in_str]
      end

      def collapse_spaces(rest, i, out)
        out << " "
        i += 1
        i += 1 while rest[i] == " "
        [i, nil]
      end
    end
  end
end
