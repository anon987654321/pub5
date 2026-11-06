# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:130 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9899417a519b1d7c
require_relative "master/law/html"

Law.define(:I18N_COVERAGE) do
  path "/app/views/"
  source "Rails i18n best practice (no hardcoded strings)"
  scope :file
  # Element content, not attribute text. Three shapes were being read as prose
  # and none of them renders as any:
  #
  # A `>` inside a quoted attribute closes nothing — `data-action="click->
  # media-picker#trigger"` made the Stimulus arrow look like a tag end, so the
  # attribute name after it counted as content and a fully translated button
  # was a finding. Quoted spans blank first.
  #
  # An ERB tag is blanked whole rather than left to look like a tag boundary.
  # `<%= @summary[:active_items] %> active</span>` is a real finding — "active"
  # is English on a Norwegian page — so the `%>` cannot simply be excluded; what
  # has to go is the expression inside it, which is Ruby and not prose.
  #
  # And an ERB comment renders nothing at all — including its continuation
  # lines, which a per-line detector cannot see past the line that opens the
  # comment. The comments are blanked before the lines are read.
  detect do |text|
    # The marker usually lives inside the ERB comment being blanked, so it is
    # consulted on the original line, which survives line-for-line.
    original = text.lines
    text.gsub(/<%#.*?%>/m) { |c| c.gsub(/[^\n]/, " ") }
        .each_line.with_index.any? do |line, i|
      next false if original[i].to_s.match?(/scan:\s*intentional\b/)

      line.gsub(/<%.*?%>/, " ")
          .gsub(/"[^"\n]*"|'[^'\n]*'/) { |m| "\0" * m.length }
          .match?(/>\s*[A-Za-z][^<]{3,}</)
    end
  end
  fix "Replace literal with t('.key')."
  bad  "<p>Welcome back</p>"
  good "<p><%= t('.welcome') %></p>"
end
