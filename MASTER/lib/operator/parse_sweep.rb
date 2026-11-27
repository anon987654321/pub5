# frozen_string_literal: true

# Prism ships with Ruby 3.3+. On an older Ruby the sweep falls back to the
# interpreter's own parser instead of dying with a LoadError (2026-11-23: a
# Ruby 3.2 host crashed `fix-here --dry` on this require).
begin
  require "prism"
rescue LoadError
  nil
end

module Operator

  # Does every Ruby file in the tree parse? Answered in one process with Prism,
  # so the whole repository takes seconds where `ruby -c` per file takes minutes.
  #
  # The pre-commit hook already refuses a staged file that does not parse, and a
  # missing comma in command_registry/chat.rb still sat on main for three hours:
  # the hook lives in a core.hooksPath that only `bin/operator hooks` sets, and
  # the clone that committed it never ran that. A check that depends on being
  # installed is not a check, so this one is run by the things that cannot skip
  # it: doctor, fix-here before it spends a model call, and CI on every push.
  module ParseSweep
    Failure = Data.define(:path, :line, :message)

    module_function

    # A git that cannot list the tree has measured nothing, so it raises rather than
    # reporting an empty list that every caller reads as "everything parses".
    def tracked(root)
      out = IO.popen(["git", "-C", root, "ls-files", "-z", "--", "*.rb"], err: File::NULL, &:read)
      raise "parse_sweep: git ls-files failed under #{root}" unless $?.success?

      out.split("\0").reject(&:empty?)
    end

    # Check MASTER and the target's dependency tree before repair.
    def paths_for(root, target)
      base = File.expand_path(root)
      absolute = File.expand_path(target, base)
      return tracked(root) if absolute == base || !absolute.start_with?("#{base}/")

      scope = absolute.delete_prefix("#{base}/")
      scope = "RAILS" if scope.start_with?("RAILS/")
      tracked(root).select do |path|
        ["MASTER", scope].any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
      end
    end

    def failures(root, paths = tracked(root))
      paths.filter_map do |path|
        full = File.join(root, path)
        next unless File.file?(full)

        error = parse_error(full)
        Failure.new(path:, line: error[0], message: error[1]) if error
      end
    end

    # [line, message] of the first syntax error, or nil when the file parses.
    def parse_error(full)
      if defined?(Prism)
        error = Prism.parse_file(full).errors.first
        return error && [error.location.start_line, error.message]
      end

      parse_error_without_prism(full)
    end

    # compile only parses; nothing in the file is run.
    def parse_error_without_prism(full)
      RubyVM::InstructionSequence.compile(File.read(full, encoding: "UTF-8"), full)
      nil
    rescue SyntaxError => e
      first = e.message.lines.first.to_s
      [first[/#{Regexp.escape(full)}:(\d+)/, 1].to_i, first.sub(/\A.*?:\d+:\s*/, "").strip]
    end

    def render(failures)
      failures.map { |f| "#{f.path}:#{f.line}, #{f.message}" }.join("\n")
    end
  end
end
