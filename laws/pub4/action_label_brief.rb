# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/html.rb:513 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 980b0500c2d430de
require_relative "master/law/html"

module Law
  ::Law.define(:ACTION_LABEL_BRIEF) do
    source "Krug, Don't Make Me Think: omit half the words, then half again; minimalism.yml microcopy.label_max_words"
    tags %i[BE_CONCISE]
    path %r{\.(?:html\.)?erb\z}
    reads_beyond_file true
    ask "Does each button or action label lead with its verb? Rank the labels that do not and explain why; " \
        "the model may rank and explain but a person decides."
    practice "A model's verdict on verb-first labels is a ranked suggestion with its reason; the operator decides."
    fix "Cut the label to three words or fewer, verb first: \"Legg i kurv\"."
    bad "<%= button_to \"Trykk her hvis du vil legge varen i kurven\", cart_path %>\n"
    good "<%= button_to \"Legg i kurv\", cart_path %>\n"
    check do |src, path|
      src.each_line.with_index(1).filter_map do |line, n|
        count = M.words(M.label(M.action_label(line).to_s, path))
        level = count > 5 ? "warning" : "info"
        finding(line: n, message: "action label of #{count} words - #{level}: three, verb first") if count > 3
      end
    end
  end
end
