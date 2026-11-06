# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:533 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6f24821c134de703
require_relative "master/law/html"

module Law
  ::Law.define(:SELF_EVIDENT_DATA_UNLABELLED) do
    source "Refactoring UI, labels are a last resort"
    tags %i[DESIGN UX]
    path %r{/app/views/(?!.*_form).*\.erb\z}
    ask "Does this display view label data whose form already says what it is (an email, a phone number, a price, " \
        "a date)? Rank and explain; a person decides."
    practice "A model may rank unneeded labels and explain them; the operator decides which stay."
    fix "Drop the visible label and keep it for assistive tech (a visually-hidden dt, or one label for the list)."
    bad "<dt>E-post:</dt>\n<dd><%= mail_to user.email %></dd>\n"
    good "<dd><%= mail_to user.email %></dd>\n"
    check do |src, _path|
      lines = src.lines
      lines.each_index.filter_map do |index|
        (message = M.unneeded_label(lines, index)) && finding(line: index + 1, message:)
      end
    end
  end
end
