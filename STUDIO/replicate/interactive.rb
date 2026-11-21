# frozen_string_literal: true

module Studio
  # The shared question-asker for the STUDIO tools.
  #
  # Each tool is an interactive CLI: run it with no arguments and it asks what to
  # do, so an operator never has to remember a flag. The flags still work, for
  # scripts and for the tests that call the libraries directly.
  #
  # Answers come from $stdin/$stdout. A caller can pass input/output (the tests
  # do), and when the input is not a terminal every question takes its default,
  # so a piped, redirected or automated run never blocks on a prompt.
  class Interactive
    def initialize(input: $stdin, output: $stdout, tty: nil)
      @input = input
      @output = output
      @tty = tty.nil? ? (input.respond_to?(:tty?) && input.tty?) : tty
    end

    def tty? = @tty

    # One question with a default. A blank answer keeps the default.
    def ask(question, default: nil)
      return default unless tty?

      @output.print(prompt(question, default))
      @output.flush if @output.respond_to?(:flush)
      line = @input.gets
      return default if line.nil?

      answer = line.strip
      answer.empty? ? default : answer
    end

    # A numbered choice. `options` is a list of strings, or of [label, value]
    # pairs when the label shown and the value returned differ. Returns the
    # chosen value (the string itself for a plain list).
    def choose(question, options, default: nil)
      raise ArgumentError, "choose needs at least one option" if options.empty?

      labels = options.map { |option| option.is_a?(Array) ? option.first : option }
      values = options.map { |option| option.is_a?(Array) ? option.last : option }
      return values.first unless tty?

      @output.puts(question)
      labels.each_with_index { |label, index| @output.puts("  #{index + 1}) #{label}") }
      default_index = default ? values.index(default) : 0
      picked = ask("Choose", default: (default_index || 0) + 1)
      index = picked.to_i
      index.between?(1, values.size) ? values[index - 1] : values[default_index || 0]
    end

    # A yes/no question; `default` decides what a blank answer means.
    def confirm(question, default: true)
      return default unless tty?

      hint = default ? "Y/n" : "y/N"
      answer = ask("#{question} [#{hint}]", default: default ? "y" : "n").to_s.strip.downcase
      answer.start_with?("y")
    end

    # A number within a range, re-asking on nonsense in a real session.
    def number(question, default:, range:)
      return default unless tty?

      answer = ask("#{question} (#{range})", default: default)
      value = Integer(answer.to_s, exception: false)
      value && range.cover?(value) ? value : default
    end

    private

    def prompt(question, default)
      default.nil? ? "#{question}: " : "#{question} [#{default}]: "
    end
  end
end
