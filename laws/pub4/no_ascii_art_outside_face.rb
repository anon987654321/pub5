# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/lexical.rb:536 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 9158b8ffe0d4e4d8
require_relative "master/law/lexical"

module Master
  module Review
    module Scan
      module Laws
  ::Law.define(:NO_ASCII_ART_OUTSIDE_FACE) do
    source "Rendered-values law - ASCII art is reserved for the face itself"
    ask "Does this file add ASCII-art logos, boot banners, decorative prompt drawings, or other " \
        "typographic pictures outside the face renderer? ASCII art is forbidden everywhere except " \
        "the face itself and the fixtures that prove its rendering. Ordinary text, a real wordmark " \
        "set in a font, shell prompt characters, and dmesg-like status lines are not ASCII art. " \
        "Return CLEAN when no decorative ASCII picture exists outside the face."
    tags %i[BE_CONCISE]
    fix "Delete ASCII-art banners, wordmarks, and prompt drawings. Keep ASCII geometry only inside " \
        "the terminal/browser face renderer and its matching fixtures."
    bad "ascii_art: true\n"
    good "prompt = \"~/repo main %\"\n"
    check do |src, path|
      next [] if path.to_s.match?(FACE_ASCII_EXCEPTIONS)

      lines = src.lines
      findings = []
      art_row = lambda do |line|
        visual = line.to_s.strip.sub(/\A(?:#|\/\/)\s*/, "").delete(" \t'\",")
        symbols = visual.scan(/[|\/\\_+=*#~^<>-]/).length
        visual.length >= 8 && symbols >= 4 && symbols.fdiv(visual.length) >= 0.33
      end

      lines.each_with_index do |line, index|
        next if line.match?(/scan:\s*intentional\b/)
        next unless line.match?(/^\s*(?:ascii_art|ascii_logo|banner_art)\s*:/)

        findings << finding(line: index + 1, message: "remove ASCII art; only the face renderer may draw it")
      end

      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*wordmark\s*:/)
        next unless lines[(index + 1), 5].to_a.any? { |candidate| art_row.call(candidate) }

        findings << finding(line: index + 1, message: "remove ASCII art; only the face renderer may draw it")
      end

      art_lines = lines.each_with_index.filter_map { |line, index| index if art_row.call(line) }
      art_lines.each_with_index do |index, position|
        next if position.positive? && index == art_lines[position - 1] + 1
        next unless art_lines[position + 1] == index + 1

        findings << finding(line: index + 1, message: "remove ASCII art; only the face renderer may draw it")
      end
      findings.uniq { |item| item[:line] }
    end
  end
      end
    end
  end
end
