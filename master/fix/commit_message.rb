# frozen_string_literal: true

module Fix
  # Every commit /fix makes (PLAN.md section 6.3). pub4 /fix committed
  # "Fix_loop: fast-fix [pass 1]" and "ABC_SIZE in baymard_law.rb" with a
  # one-line body or none (pub4 7600739e08); a three-Law subject ran past 72
  # characters and the cut dropped the file (pub4 94ff01dcbf).
  #
  # The shape: a capitalised subject of at most 72 characters that keeps the
  # file name, a body of what changed and why wrapped at 72 columns, the
  # measured delta, the MARKER line that tells /fix's commits from other
  # writers', and the trailers Law:, Measured:, Writer:, Proof:.
  module CommitMessage
    MARKER = "Written by MASTER /fix"
    LIMIT = 72
    # "fix_loop:", "stream_fix:": a label no reader wants as a subject.
    LABEL = /\A[A-Za-z]+_[A-Za-z_]+:/
    TRAILERS = %w[Law Measured Writer Proof].freeze

    module_function

    def compose(subject, what:, why:, trailers:, details: [])
      body = wrap("#{sentence(what)} #{sentence(why)}")
      lines = [fit(subject), "", body, *(details.empty? ? [] : ["", *details]), "", MARKER, ""]
      lines += TRAILERS.map { |key| "#{key}: #{trailers.fetch(key.downcase.to_sym)}" }
      check!(lines.join("\n"))
    end

    # One repair of one file. The finding's own words stay out of the
    # message: they are evidence about the code, and a finding that says
    # "extract" would read as a refactor the repair never claimed.
    def repair(laws:, file:, line:, before:, after:, writer:, proof:)
      laws = Array(laws).map(&:to_s).uniq
      noun = laws.size == 1 ? "finding" : "findings"
      compose(repair_subject(laws, File.basename(file)),
              what: "/fix rewrote #{file} near line #{line} to clear its #{listed(laws)} #{noun}",
              why: "The change passed the parse gate, the rescan, the scope check and the file's tests",
              trailers: { law: laws.join(", "), measured: "#{before} -> #{after} findings in #{file}",
                          writer:, proof: })
    end

    # The deterministic writes of one pass (whitespace transforms), delivered together.
    def autofix(paths:, laws:, writer:)
      compose("Apply the deterministic fixes of this /fix pass",
              what: "Commits the mechanical rewrites the pass made to #{paths.size} file(s)",
              why: "Each file still holds exactly the bytes the transform wrote and still parses",
              details: paths.first(20).map { |path| "- #{path}" },
              trailers: { law: laws.join(", "), measured: "#{paths.size} file(s) rewritten", writer:,
                          proof: "parse gate on every file" })
    end

    # The file name always survives: a subject cut at 72 lost it and ended on "in".
    def repair_subject(laws, name)
      full = "Repair #{listed(laws)} in #{name}"
      return full if full.size <= LIMIT

      short = "Repair #{laws.first} and #{laws.size - 1} more in #{name}"
      laws.size > 1 && short.size <= LIMIT ? short : "Repair #{name}"
    end

    def listed(laws) = laws.size <= 2 ? laws.join(" and ") : "#{laws[0..-2].join(', ')} and #{laws.last}"

    def check!(text)
      found = problems(text)
      raise ArgumentError, "a /fix commit message breaks the commit format: #{found.join('; ')}" if found.any?

      text
    end

    # The house format (AGENTS.md "Commit format", .githooks/commit-msg) plus
    # what a /fix commit owes beyond it: a body, the marker and the trailers.
    def problems(text)
      lines = text.to_s.strip.lines.map(&:chomp)
      subject = lines.first.to_s
      found = []
      found << "the subject must open with a capital letter" unless subject.match?(/\A[A-Z]/)
      found << "the subject is not plain ASCII" if subject.match?(/[^ -~]/)
      found << "the subject is one word" if subject.split.size < 2
      found << "the subject is over #{LIMIT} characters" if subject.size > LIMIT
      found << "the subject ends in punctuation" if subject.end_with?(*%w[. ! , : ;])
      found << "the subject starts with a label (#{subject[LABEL]})" if subject.match?(LABEL)
      found << "a /fix commit needs a body saying what changed and why" unless body?(lines)
      found << "a /fix commit carries the line #{MARKER.inspect}" unless lines.include?(MARKER)
      TRAILERS.each { |key| found << "missing the #{key}: trailer" unless lines.any? { |l| l.start_with?("#{key}: ") } }
      found
    end

    def own?(message) = message.to_s.lines.map(&:chomp).include?(MARKER)

    def body?(lines)
      lines.drop(2).take_while { |line| line != MARKER }.any? { |line| !line.strip.empty? }
    end

    def sentence(text)
      said = text.to_s.gsub(/\s*[–—]\s*/, ", ").gsub(/\s+/, " ").strip
      said.match?(/[.!?]\z/) ? said : "#{said}."
    end

    def wrap(text) = text.scan(/\S.{0,71}(?=\s|\z)|\S+/).join("\n")

    def fit(subject)
      text = subject.to_s.strip.sub(/[.!,:;]+\z/, "")
      text = "#{text[0].upcase}#{text[1..]}" unless text.empty?
      return text if text.size <= LIMIT

      text[0, LIMIT + 1].sub(/\s+\S*\z/, "")
    end
  end
end
