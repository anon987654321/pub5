# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:519 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: a9881878ee8ab9e9
require_relative "master/law/css"

module Law
  ::Law.define(:PRINT_PAGE_CANON) do
    source "Tschichold, The Form of the Book (1991): the 2:3:4:6 canon from Van de Graaf and Villard; Bringhurst ch. 8"
    tags %i[TYPOGRAPHY]
    path %r{(?:\A|/)BPLANS/}
    example_path "/repo/BPLANS/print.css"
    fix "Set @page margins inner < top < outer < bottom near 2:3:4:6 (22mm 33mm 44mm 66mm), mirrored on :left, " \
        "and the measure at 55-75ch."
    bad "@page { margin: 20mm; }\n"
    good "@page :right { margin: 33mm 44mm 66mm 22mm; }\n@page :left { margin: 33mm 22mm 66mm 44mm; }\n"
    check { |src, _path| P.page_findings(src).map { |message, at| finding(line: P.line_at(src, at), message:) } }
  end
end
