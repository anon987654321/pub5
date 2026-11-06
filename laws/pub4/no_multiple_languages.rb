# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:83 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 0b622fccc2d32f77
require_relative "master/law/css"

Law.define(:NO_MULTIPLE_LANGUAGES) do
  source "MASTER-native (one language per file)"
  ask "Does this file embed multiple languages or notations, or does the artifact mix incompatible frameworks or media layers?"
  # A regex that matches `<%` is not ERB, and a string naming a heredoc tag is
  # not a heredoc. Unmasked this flagged the scanner's own ERB detectors, the
  # source-masking constants and css_coverage_lint's comment stripper — 35 of 72
  # findings were code ABOUT an embedded language rather than an instance of one,
  # which is the shape law.rb's `conduct` already neutralises for law/ itself.
  #
  # A heredoc bound to a constant is exempt because it is the fix: `good` here is
  # `connection.exec(query)`, meaning the other language lives in a name rather
  # than inside a call. PROBE = <<~JS and SCHEMA = <<~SQL are already that, and
  # flagging them asks for a change the rule cannot describe.
  # Strings are not masked, and must not be: `template = "<%= x %>"` is a Ruby
  # file carrying an ERB template, which is the defect exactly, and blanking
  # string literals made the rule blind to its own primary case. What
  # distinguishes it from a scanner naming the delimiter is completeness — an
  # ERB tag opens and closes. `ERB_OPEN = "<%"` is a pattern; `"<%= x %>"` is a
  # template. Regexes stay masked, since `/<%|<script\b/` is a detector.
  detect do |line|
    next false if line.match?(/\A\s*[A-Z][A-Z0-9_]*\s*=\s*<<[~-]/)
    # A needle is not a template. The source checks search a file for the exact
    # text they require — `body.include?('import("<%= asset_path(...) %>")')` —
    # and the ERB tag there is the thing being looked for, not a second language
    # this file speaks.
    next false if line.match?(/\.(?:include\?|match\?|scan|index|start_with\?|end_with\?)\(/)

    masked = line.gsub(Regexp.new('(?<![\w)\]])/(?:[^/\\\\\n]|\\\\.)+/[mixo]*')) { |m| "\0" * m.length }
    masked.gsub!(/%r[{(\[](?:[^})\]\\]|\\.)*[})\]][mixo]*/) { |m| "\0" * m.length }
    masked.match?(/<%.*%>|<script\b|<style\b|<<[~-]?["'`]?(?:SQL|HTML|CSS|JS|JAVASCRIPT)\b/)
  end
  fix "One language per layer. Separate into distinct files or clearly demarcated sections."
  bad  "rows = connection.exec(<<~SQL)"
  good "rows = connection.exec(query)"
end
