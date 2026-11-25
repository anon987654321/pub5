# frozen_string_literal: true

module Master
  module Voice
    class Renderer
      # Text transformation/formatting helpers — separate from Renderer's
      # own render/output-guard responsibility.
      module TextFormatting
        # Preserve authored line and paragraph boundaries. Terminals soft-wrap at
        # the viewport edge; inserting newline characters here corrupts copied
        # text, streamed paragraphs and transcripts. width remains accepted for
        # callers that used the old signature.
        MEASURE = 72

        def measure(text, **_options)
          text.to_s
        end

        # Render common Markdown without changing authored line lengths or
        # paragraph boundaries. Fences, tables and record lines keep their shape.
        def terminal_markdown(text, width: MEASURE)
          # The CLI's presentation path must retain the same evidence guard as
          # Renderer#render; Markdown cleanup is not a second trust boundary.
          source = output_guard.sanitize(text.to_s, context: :routine)
          rows = []
          fenced = false
          language = ""

          source.lines.each do |line|
            body = line.chomp
            if body.lstrip.start_with?("```")
              language = fenced ? "" : body.lstrip.delete_prefix("```").strip.downcase
              fenced = !fenced
              rows << "" if rows.any? && !rows.last.empty?
              next
            end

            if fenced
              rows << (body.empty? ? "" : "    #{highlight_terminal_code(body, language:)}")
              next
            end

            next rows << "" if body.empty?

            if (heading = body.match(/\A\s{0,3}\#{1,6}\s+(.+)\z/))
              rows.concat(measure(heading[1], width:).lines(chomp: true).map { |row| markdown_emphasis(row) })
              next
            end

            if body.match?(/\A\s{0,3}(?:---+|\*\*\*+|___+)\s*\z/)
              rows << "----"
              next
            end

            body = body.sub(/\A\s{0,3}>\s?/, "  ")
            body = body.sub(/\A\s{0,3}\*\s+/, "- ")
            body = body.gsub(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/) do
              label = Regexp.last_match(1)
              url = Regexp.last_match(2)
              label == url ? url : "#{label} (#{url})"
            end
            body = body.gsub(/\*\*(.+?)\*\*/) { Regexp.last_match(1) }
            body = body.gsub(/(?<!\*)\*([^*\n]+)\*(?!\*)/) { Regexp.last_match(1) }
            body = body.gsub(/__([^_\n]+)__/) { Regexp.last_match(1) }
            body = body.gsub(/`([^`\n]+)`/) { Regexp.last_match(1) }
            rows.concat(measure(beautify(body), width:).lines(chomp: true))
          end

          rows.join("\n") + (source.end_with?("\n") ? "\n" : "")
        end


        # One portable lexical grammar, projected into the browser at boot.
        # Patterns share the Ruby/ECMAScript subset; no inner capture groups.
        TERMINAL_GRAMMARS = {
          'ruby' => [
            ['comment', '#[^\\r\\n]*'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '\\b(?:alias|and|begin|break|case|class|def|defined|do|else|elsif|end|ensure|false|for|if|in|module|next|nil|not|or|redo|rescue|retry|return|self|super|then|true|undef|unless|until|when|while|yield)\\b'],
            ['command', '\\b(?:puts|print|warn|printf|echo|ruby|bundle|rake|git|cd|pwd|ls|cat|grep|rg|sed|awk|find|doas|sudo|chmod|chown|install|make|node|npm|ssh|scp|tar|env|curl|pkg_add|service|rcctl)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b'],
            ['type', '\\b[A-Z][A-Za-z0-9_]*\\b']
          ],
          'shell' => [
            ['comment', '#[^\\r\\n]*'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\'|\\x60(?:\\\\.|[^\\x60\\\\])*\\x60'],
            ['keyword', '\\b(?:if|then|else|elif|fi|for|while|until|do|done|case|esac|in|function|export|local|readonly|return|exit)\\b'],
            ['option', '--?[A-Za-z][\\w-]*'],
            ['variable', '\\$(?:\\{[^}\\r\\n]+\\}|[A-Za-z_]\\w*|[0-9?@#*])'],
            ['command', '\\b(?:puts|print|warn|printf|echo|ruby|bundle|rake|git|cd|pwd|ls|cat|grep|rg|sed|awk|find|doas|sudo|chmod|chown|install|make|node|npm|ssh|scp|tar|env|curl|pkg_add|service|rcctl)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'javascript' => [
            ['comment', '//[^\\r\\n]*|/\\*[\\s\\S]*?(?:\\*/|$)'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\'|\\x60(?:\\\\.|[^\\x60\\\\])*\\x60'],
            ['keyword', '\\b(?:as|async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|false|finally|for|from|function|get|if|import|in|instanceof|let|new|null|of|return|set|static|super|switch|this|throw|true|try|typeof|undefined|var|void|while|with|yield|interface|type|enum|implements|private|public|protected|readonly|satisfies)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'css' => [
            ['comment', '/\\*[\\s\\S]*?(?:\\*/|$)'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '@[\\w-]+|--[\\w-]+|[\\w-]+(?=\\s*:)'],
            ['number', '#[0-9a-fA-F]{3,8}\\b|\\b\\d+(?:\\.\\d+)?(?:px|em|rem|vh|vw|ms|s|deg|%)?']
          ],
          'html' => [
            ['comment', '<!--[\\s\\S]*?(?:-->|$)'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '</?[A-Za-z][\\w:-]*|[\\w:-]+(?=\\s*=)'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'json' => [
            ['keyword', '"(?:\\\\.|[^"\\\\])*"(?=\\s*:)'],
            ['string', '"(?:\\\\.|[^"\\\\])*"'],
            ['keyword', '\\b(?:true|false|null)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'yaml' => [
            ['comment', '#[^\\r\\n]*'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '[\\w.-]+(?=\\s*:)|\\b(?:true|false|null)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'python' => [
            ['comment', '#[^\\r\\n]*'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '\\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'sql' => [
            ['comment', '--[^\\r\\n]*|/\\*[\\s\\S]*?(?:\\*/|$)'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '\\b(?:select|from|where|join|inner|outer|left|right|on|insert|into|update|set|delete|create|table|alter|drop|as|and|or|not|null|true|false|group|by|order|having|limit|offset|values|union|distinct|case|when|then|else|end|begin|commit|rollback|primary|key)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ],
          'compiled' => [
            ['comment', '//[^\\r\\n]*|/\\*[\\s\\S]*?(?:\\*/|$)'],
            ['string', '"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\''],
            ['keyword', '\\b(?:auto|bool|break|case|char|class|const|continue|default|do|double|else|enum|extern|false|float|fn|for|func|if|impl|import|int|let|long|match|mod|namespace|new|nil|null|package|private|public|return|short|static|struct|super|switch|this|trait|true|type|typedef|union|unsigned|use|var|void|while)\\b'],
            ['number', '\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b']
          ]
        }.transform_values { |rows| rows.map(&:freeze).freeze }.freeze
        TERMINAL_ALIASES = { 'rb' => 'ruby', 'sh' => 'shell', 'bash' => 'shell', 'zsh' => 'shell', 'js' => 'javascript', 'ts' => 'javascript', 'typescript' => 'javascript', 'jsx' => 'javascript', 'tsx' => 'javascript', 'scss' => 'css', 'sass' => 'css', 'xml' => 'html', 'svg' => 'html', 'erb' => 'html', 'yml' => 'yaml', 'py' => 'python', 'c' => 'compiled', 'cpp' => 'compiled', 'go' => 'compiled', 'rust' => 'compiled', 'java' => 'compiled' }.freeze

        def self.browser_grammar
          { grammars: TERMINAL_GRAMMARS, aliases: TERMINAL_ALIASES, insensitive: ["sql"] }
        end

        def highlight_terminal_code(line, language: "")
          return line unless terminal_color_enabled?

          language = TERMINAL_ALIASES.fetch(language, language)
          rules = TERMINAL_GRAMMARS[language]
          return line unless rules

          pattern = Regexp.new(rules.map { |_, source| "(#{source})" }.join("|"),
            language == "sql" ? Regexp::IGNORECASE : 0)
          line.gsub(pattern) do |token|
            role = rules[Regexp.last_match.captures.index { |capture| !capture.nil? }].first
            case role
            when "comment" then @p.dim(token)
            when "string" then @p.green(token)
            when "option", "variable" then @p.yellow(token)
            when "keyword" then @p.cyan(token)
            when "number" then @p.magenta(token)
            when "command" then @p.bold(@p.cyan(token))
            when "type" then @p.blue(token)
            else token
            end
          end
        rescue StandardError
          line
        end

        def format_dmesg(line) = @p.dim(line.to_s)

        # The terminal prints ASCII (operator, 2026-11-06), so prose leaves
        # here as straight quotes, "-" and "...":
        # a double hyphen between words becomes the one hyphen, and the
        # double space after a sentence closes to one. Record lines (a "=" or
        # a URL) carry data and keep their spacing as written.
        def beautify(text)
          text.lines.map do |line|
            next line if line.include?("=") || line.include?("://")

            line.gsub(/\s--\s/, " - ").gsub(/([.!?])  +(?=\S)/, "\\1 ")
          end.join
        end

        private

        def markdown_emphasis(text)
          return text unless $stdout.tty?

          @p.bold(text)
        rescue StandardError
          text
        end
      end
    end
  end
end
