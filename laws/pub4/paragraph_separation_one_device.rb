# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/css.rb:502 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 48e9ed7dc8800b1a
require_relative "master/law/css"

module Law
  ::Law.define(:PARAGRAPH_SEPARATION_ONE_DEVICE) do
    source "Bringhurst 2.3.1-2.3.2; Butterick, indent or space, don't use both; Tschichold, The Form of the Book"
    tags %i[TYPOGRAPHY]
    snap = Deploy::RenderedDesign
    path Regexp.union(/\.s?css\z/, snap::SNAPSHOT)
    fix "Separate paragraphs by space (p + p { margin-block-start }) or by an indent of one en, never both; " \
        "never indent the first."
    bad "p { margin-block: 1.5em; text-indent: 1em; }\n"
    good "p + p { margin-block-start: 1.5em; }\n"
    check { |src, _path| P.both_devices(src).map { |hit| finding(**hit) } }
    adapter(:rendered_ui, languages: %i[json], example_path: snap::EXAMPLE,
                          bad: snap.fixture(elements: P.paragraphs(text_indent: 16, margin_block: [24, 24])),
                          good: snap.fixture(elements: P.paragraphs(margin_block: [0, 24]))) do |text, file|
      snap.findings(:PARAGRAPH_SEPARATION_ONE_DEVICE, text, file).map { |hit| finding(**hit) }
    end
  end
end
