# frozen_string_literal: true

require "prism"
require "erb"
require "json"
require "yaml"
require "date"

module Core
  # The parse gate: Ruby, YAML, JSON and ERB must parse before anything else
  # is asked of them. pub4 logged 177 parse or syntax repair commits in 30
  # days; here a file that does not parse never reaches a commit.
  module ParseGate
    RUBY = %w[.rb .rake .ru .gemspec].freeze
    # Rails writes `<%= form_with do |f| %>`; stdlib ERB would wrap the block in
    # a `.to_s` call and report a syntax error the real template does not have.
    # The body may not cross a closing `%>`, so the fixup rewrites the one tag
    # it names and never a plain `<%= t(:x) %>` sitting before it.
    BLOCK_OUTPUT = /<%=((?:(?!%>)[\s\S])*?\bdo\b\s*(?:\|[^|]*\|)?\s*)-?%>/m
    # The erb source opens with two lines that are no template's own - the
    # `def` line and ERB's unconditional `#coding:UTF-8` - so an error's line
    # number is reported two lines early.
    ERB_CONTEXT_LINES = -2

    module_function

    def kind(path)
      ext = File.extname(path)
      return :ruby if RUBY.include?(ext) || File.basename(path) == "Gemfile" || ruby_script?(path)
      return :yaml if %w[.yml .yaml].include?(ext)
      return :json if ext == ".json"

      :erb if ext == ".erb"
    end

    # Files under bin/ with a ruby shebang are Ruby too.
    def ruby_script?(path)
      File.extname(path).empty? && File.file?(path) && File.open(path, &:gets).to_s.start_with?("#!/usr/bin/env ruby")
    end

    # The first problem in a file's text, or nil when it parses.
    def problem(kind, text)
      case kind
      when :ruby then ruby_problem(text)
      when :yaml then Registry.parse(text) && nil
      when :json then JSON.parse(text) && nil
      when :erb then ruby_problem(erb_src(text), line_offset: ERB_CONTEXT_LINES)
      end
    rescue Psych::Exception, JSON::ParserError, SyntaxError => e
      e.message.lines.first.to_s.strip
    end

    # Rails compiles a template into a method, where `yield` (a layout's
    # content hook) is legal; stdlib ERB emits flat source where it is not.
    # Parse inside that method body and shift the reported line back.
    def erb_src(text)
      "def __template;\n" +
        ERB.new(text.gsub(BLOCK_OUTPUT) { "<%#{Regexp.last_match(1)}%>" }, trim_mode: "-").src + "\nend"
    end

    def ruby_problem(text, line_offset: 0)
      error = Prism.parse(text).errors.first
      error && "line #{error.location.start_line + line_offset}: #{error.message}"
    end

    # [[path, problem]] for every file that does not parse; paths are relative to root.
    def check(paths, root: ROOT)
      paths.filter_map do |path|
        full = File.expand_path(path, root)
        next unless File.file?(full) && (k = kind(full))

        found = problem(k, File.read(full))
        [path, found] if found
      end
    end
  end
end
