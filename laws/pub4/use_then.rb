# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:422 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: ff46a1601a3db0ca
require_relative "master/law/ruby"

Law.define(:USE_THEN) do
  source "Ruby idiom - Object#then (yield_self) for pipelines"
  scope :file
  # The same defect GUARD_CLAUSE carried and had fixed above: `/m` makes `.`
  # match newlines, so `\(.*\)` ran to the last paren in the file and any file
  # holding an assignment and a later call matched. scope :file then reports it
  # at line 1, so every hit pointed at frozen_string_literal.
  #
  # The pair has to be adjacent to be a pipeline — that is the whole idea the
  # rule is about, and it is what the fixtures show. [^\n]* keeps the call on
  # its own line.
  # The binding has to die at that second call. Adjacency alone says nothing
  # about whether the name is used again, and in this tree it usually is:
  # DiffStager builds an entry, persists it, and then publishes and returns
  # three of its fields. Chaining that drops a variable the rest of
  # the method needs — applying this rule to its own eight findings introduced
  # three NameErrors, which is how the check below was earned.
  #
  # `then` is only an improvement where the intermediate exists to be handed on
  # once. Everything after the pair, down to the end of the enclosing block, has
  # to be free of the name.
  detect do |text|
    text.enum_for(:scan, /^([ \t]*)(\w+)\s*=\s*\w+\([^\n]*\)\n[ \t]*\w+\(\2\)/).any? do
      match = Regexp.last_match
      indent = match[1].length
      rest = text[match.end(0)..].to_s.lines
      stop = rest.index { |line| !line.strip.empty? && line[/\A[ \t]*/].length < indent }
      (stop ? rest[0...stop] : rest).join.match?(/\b#{Regexp.escape(match[2])}\b/) == false
    end
  end
  fix "Chain with .then { |r| next_step(r) }"
  bad <<~X
    r = parse(src)
    render(r)
  X
  good <<~X
    parse(src).then { |r| render(r) }
  X
end
