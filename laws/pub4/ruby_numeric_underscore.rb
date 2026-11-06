# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb:297 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b5cf2b58652a66e3
require_relative "master/law/ruby"

Law.define(:RUBY_NUMERIC_UNDERSCORE) do
  source "Ruby Style Guide / RuboCop Style/NumericLiterals"
  # A long run of digits inside a string is not a numeric literal. Unmasked, this
  # read a port out of "http://127.0.0.1:38182/", an ffmpeg filter's
  # sample_rates=44100, the hex in '#010203', and the digits in this rule's own
  # fix line — 107 findings of which 81 were quoted text. Strings, regexes and
  # trailing comments are blanked before the digits are counted, and a preceding
  # colon or word character rules out a port or an identifier.
  detect do |line|
    masked = line.dup
    masked.gsub!(/"(?:[^"\\]|\\.)*"/) { |m| "\0" * m.length }
    masked.gsub!(/(?:[^\w?\\]|\A)'(?:[^'\\]|\\.)*'/) { |m| "\0" * m.length }
    masked.gsub!(%r{/(?:[^/\\\n]|\\.)+/}) { |m| "\0" * m.length }
    if (at = masked.index(/(?<!['"\0])#/))
      masked[at..] = "\0" * (masked.length - at)
    end
    # `=` joins the lookbehind. A heredoc has no quotes to blank, so the ffmpeg
    # graphs in mix_recipes.rb arrived unmasked and every `sample_rates=44100`
    # and `equalizer=f=12000` read as a Ruby literal — 23 findings whose fix
    # would have written `44_100` into a filter string and broken the render.
    # Ruby spaces its assignment; a `=` flush against the digits is a config
    # token in some other language.
    masked.match?(/(?<![\w.:=])\d{5,}(?![\d_])/)
  end
  fix "Group digits in threes: one million is 1_000_000."
  bad  "max = 1000000"
  good "max = 1_000_000"
end
