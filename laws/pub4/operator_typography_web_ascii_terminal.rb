# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/data/project_context.yml operator_typography_web_ascii_terminal by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: b6db39e95ef40623
require_relative "master/lib/master"

Law.define(:OPERATOR_TYPOGRAPHY_WEB_ASCII_TERMINAL) do
  source "pub4 MASTER/data/project_context.yml operator_typography_web_ascii_terminal"
  practice "ASCII marks (a hyphen, three dots, straight quotes, ->) belong to the CLI,\nthe shell and REPL prompt, the terminal face and dmesg or log lines; that\nwas the ban's only purpose. Web copy, locale files, views, Markdown and TeX\ndocuments, root documents and BPLANS use proper typography: the ellipsis\n(U+2026), an en dash (U+2013) in a numeric range (EN_DASH_RANGE), curly\nquotes, and for an aside a spaced en dash, \"word - aside - word\" set with\nU+2013. Norwegian copy quotes with guillemets (U+00AB, U+00BB) and single\ncurly quotes inside; English keeps curly double quotes. EN_DASH_RANGE and\nTYPOGRAPHIC_EXCELLENCE skip Law::TERMINAL_OUTPUT_PATH (law/definition.rb)\nand printing lines; PARENTHETICAL_DASH and QUOTES_BY_LOCALE\n(law/typesetting.rb) hold the aside and the quotes. The face glyph ramp\nstays as it is. Text written before 2026-11-05 keeps its original marks."
end
