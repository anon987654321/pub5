# frozen_string_literal: true

module Master
  module Voice
    # Which language a phrase is in, for phrase-level voice-family selection.
    #
    # Deliberately a small heuristic and not a classifier: the phrases are short
    # and the decision feeds a registered language family. English is the default;
    # Norwegian Bokmål and Malaysian Malay are explicit routes so they cannot
    # silently fall through to the English mouth.
    #
    # Certainty comes from two signals, either of which is decisive. A
    # Norwegian-only letter, or a word that is not an English word at all.
    #
    # MARKERS earns its threshold of one by what it excludes rather than by
    # counting. "for", "en", "sin", "over", "under", "man" and "de" are all
    # ordinary Norwegian and all also English, so they are absent; so is "vi",
    # which is an editor here more often than a pronoun. What is left cannot
    # appear in an English sentence, so a second hit would add nothing but a
    # missed short clause -- and short clauses are exactly what phrase-level
    # detection exists for.
    module Language
      NORDIC_LETTERS = /[æøåÆØÅ]/
      MARKERS = %w[
        og ikke ikkje jeg det som til med har være er
        kan skal dette denne noen mye veldig fordi eller
        hvis hvor når dem seg sitt disse etter mellom
        ser gjør går kommer riktig ferdig faktisk
      ].freeze
      MARKER_RE = Regexp.new("(?<![\\w-])(#{MARKERS.join('|')})(?![\\w-])", Regexp::IGNORECASE)
      MALAY_MARKERS = %w[
        yang dan tidak saya ini itu untuk dengan dari pada ada akan boleh
        kita kamu kami mereka apa siapa mana sudah belum juga hanya sangat
        kerana sebab memang dalam kepada sebagai apabila
      ].freeze
      MALAY_MARKER_RE = Regexp.new("(?<![\\w-])(#{MALAY_MARKERS.join('|')})(?![\\w-])", Regexp::IGNORECASE)

      module_function

      def detect(text)
        # Language detection is also called from queue and media boundaries,
        # where a UTF-8 byte sequence can arrive tagged as ASCII-8BIT. Ruby
        # refuses to match the UTF-8 marker regexps against that encoding.
        # Normalize a private copy; never mutate the caller's string.
        body = text.to_s.dup
        if body.encoding == Encoding::BINARY
          body.force_encoding(Encoding::UTF_8)
        elsif body.encoding != Encoding::UTF_8
          body = body.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
        body = body.scrub

        return :nb if body.match?(NORDIC_LETTERS)
        return :ms if body.match?(MALAY_MARKER_RE)
        body.match?(MARKER_RE) ? :nb : :en
      end
    end
  end
end
