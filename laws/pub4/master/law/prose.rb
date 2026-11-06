# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/prose.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 41ee3c8eb56bfae6
require_relative "../lib/master"

# law/prose.rb — the prose laws, generated one pair per natural language.
#
# EN_DASH_RANGE lives once, in the registry (cosmetic_rules.rb): it also
# covers yaml and html, skips YAML list items and rule-id lines, and —
# decisive here — `prose` is not a language FILE_LANGUAGE_MAP produces, so
# half this law's declared scope never matched a file (Bringhurst's credit
# rides with the registry version).
#
# Strunk describes a shape, not a list of English words: an intensifier that
# adds emphasis and no information, a passive that hides its actor. Any language
# with those has its own words for them. Holding the words in the detector made
# these two English-only by accident, so the vocabulary, the senses to keep, the
# passive's shape and the fixtures all live in data/laws.yml under `prose:`,
# and this file turns each entry into a pair of laws. A second language is a
# data edit: a `prose:` entry and its two law_catalogue entries.
#
# Each Law is scoped to the files it is written in (its catalogue languages
# and the `path` below), and that scoping is what makes the design
# safe: Norwegian `bare` (only) is an
# English word this tree uses constantly — "a bare regex", "bare true" — so a
# vocabulary let loose outside its own files returns nothing but noise.
#
# A prose law also has to reach prose, and both of these reached the opposite of
# it. `reads_comments` defaults to false, which means considered_text blanks
# every comment before the detector runs, so in Ruby they saw the code and
# nothing else: every hit was a string literal or an identifier — `raise
# "#{path} is untracked"`, "Solid Queue must be enabled", a <<~JS heredoc. Not
# one was a sentence anybody wrote as prose. Reaching comments is half of it;
# the code lines are still in the text, which is what `reads:` settles per
# language.

module Law
  module Prose
    # Through the accessor, not a second YAML.load_file of laws.yml. A data
    # file with two loading paths is how the two drift, which is what
    # test_reader_singularity ratchets against.
    CONFIG = Master.law("prose").freeze

    # A comment that names a word in backticks is discussing the word, not using
    # it — the same distinction Law.conduct draws for a law that has to judge
    # law/ itself. Without this, these laws fire on the paragraphs explaining
    # them.
    QUOTED = /`[^`]*`/
    LEADER = /\A\s*#/
    CODE = /[=(){}\[\];|"']|\b(?:def|end|class|module|return|require)\b/
    # A locale file's key is a symbol, not a sentence.
    KEY = /\A\s*(?:-\s*)?[\w.]+:\s*/

    # The prose in a line, or nil where the line carries none. Markdown has no
    # comment leader to key on, so `comments` also takes a line with no code
    # punctuation — conservative, and it passes over a prose sentence holding a
    # quote rather than risk judging a fenced code block as English.
    def self.said(line, reads)
      text = line.gsub(QUOTED) { |match| " " * match.length }
      case reads
      when "comments" then text.match?(LEADER) || !text.match?(CODE) ? text : nil
      when "values" then text.sub(KEY, "")
      end
    end

    def self.any(patterns) = Regexp.union(patterns.map { |pattern| Regexp.new(pattern) })

    def self.words(list) = /\b(?:#{list.map { |word| Regexp.escape(word) }.join('|')})\b/

    # The files a language's prose is written in. Bokmål lives in translation values
    # and in the Norwegian business plans, whose HTML is the canonical source.
    SCOPES = { "nb" => %r{(?:\A|[/.])nb\.yml\z|(?:\A|/)BPLANS/[^/]+\.html\z} }.freeze
  end
end






































































