# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/naming.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 6f89b0a42ec3b8d4
require_relative "../lib/master"

require_relative "../lib/ground/parameterized_slug"

module Master
  module Review
    module Scan
      module Laws
        






















# TYPE_IN_NAME and NUMBERED_NAME, the two naming detectors from the old backlog's
# AST-detector backlog. AST rather than a Law line-regex because both are about
# declarations — a method, a parameter, a local, an ivar — and a regex over raw
# lines cannot tell a declaration from a mention of one in a comment.
        # A name that says what type it is says the one thing the code already
        # says. `text_str` is a String either way; the name's job was to say
        # which text.
        #
        # Three exclusions, each from a measured false positive rather than a
        # guess. `to_hash` / `from_hash` are the Ruby conversion protocol and
        # renaming them breaks it. A digest is also spelled `_hash`, and
        # `prev_hash` renamed to `prev` loses the only thing the name said. And
        # `_list` is a domain noun as often as a type: an allow_list is not an
        # Array pretending to be named, and old_string is the edit-tool schema
        # this runtime hands a model. 85 findings before those exclusions, 44 after.
        class TypeInNameLaw < Detector
          SUFFIX = /_(?:string|str|array|hash|object|list)\z/
          CONVERSION = /\A(?:to|from|as|into)_/
          DIGEST = /(?:prev|last|stable|content|commit|file|source|body|digest|checksum|chain|enacted)_hash\z/
          # old_string / new_string are the edit-tool schema this runtime
          # exposes to a model, so they are an external contract like to_hash.
          KEEP = %w[
            allow_list block_list deny_list mailing_list free_list watch_list
            skip_list word_list wait_list short_list packing_list price_list
            play_list guest_list old_string new_string old_str new_str
          ].freeze


          def check_ast(ast, _code, path:)
            return [] if ast.nil? || path.to_s.match?(%r{/(?:test|spec|fixtures)/})

            named(ast).filter_map do |line, kind, name|
              next unless flagged?(name)

              finding(line:, message: "#{kind} #{name} encodes its type - name it for what it holds")
            end.uniq
          end

          private

          def named(ast)
            rows = []
            each_node(ast, Prism::DefNode).each do |def_node|
              rows << [def_node.location.start_line, "method", def_node.name.to_s]
              parameter_names(def_node).each { |name| rows << [def_node.location.start_line, "parameter", name] }
            end
            each_node(ast, Prism::LocalVariableWriteNode).each do |node|
              rows << [node.location.start_line, "local", node.name.to_s]
            end
            each_node(ast, Prism::InstanceVariableWriteNode).each do |node|
              rows << [node.location.start_line, "ivar", node.name.to_s.delete_prefix("@")]
            end
            rows
          end

          def flagged?(name)
            name.match?(SUFFIX) && !name.match?(CONVERSION) && !name.match?(DIGEST) && !KEEP.include?(name)
          end
        end

        






        # A bare sequence number in a name, where a sibling in the same file
        # carries the same stem and a different one: mix_v7 beside mix_v11. The
        # number says there was another one and nothing about the difference.
        #
        # The sibling requirement is what makes this measurable rather than
        # noisy, and it was added after measuring. Without it: 15 findings, of
        # which fet1176, fairchild670 and stc8 are the names of real hardware —
        # an 1176 compressor, a Fairchild 670, a Coles STC-8 — and inv3 and
        # normalize_to_y1 are maths. A lone number in a name is usually a fact
        # about the world. Locals were measured and dropped for the same reason:
        # 114 findings, nearly all of them dilla and postpro, where t1 and d8 are
        # the notation the DSP is transcribed from.
        class NumberedNameLaw < Detector
          NUMBERED = /\A(.*?)(?:_v)?(\d+)\z/
          KEEP = /
            (?:sha|md|crc|base|utf|latin|iso|rfc|x|ipv|http|oauth|ec|s3|p|h|mp|
               aes|rsa|ed|argon|bcrypt|blake|id|ansi|cp|win|css|es|vips|gl|webgl|
               float|int|uint|bit|px|rem|em|ms|hz|db|k|fp|bf|q|load|capture)\d+\z
          /x


          def check_ast(ast, _code, path:)
            return [] if ast.nil? || path.to_s.match?(%r{/(?:test|spec|fixtures)/})

            numbered = stems(ast)
            by_stem = numbered.group_by { |stem, _name, _line| stem }

            numbered.filter_map do |stem, name, line|
              siblings = by_stem[stem].map { |_stem, sibling, _line| sibling }.uniq - [name]
              next if siblings.empty?

              finding(line:, message: "#{name} sits beside #{siblings.join(", ")} - the number names no difference")
            end
          end

          private

          def stems(ast)
            names = each_node(ast, Prism::DefNode).map { |node| [node.name.to_s, node.location.start_line] }
            names += each_node(ast, Prism::ClassNode).map { |node| [snake(node.name.to_s), node.location.start_line] }

            names.filter_map do |name, line|
              next if name.match?(KEEP)

              match = NUMBERED.match(name)
              next if match.nil? || match[1].empty?

              [match[1], name, line]
            end
          end

          def snake(name)
            name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
          end
        end

        






# FILE_SEQUENCE_NAME and FILE_VAGUE_NAME — the two filename detectors. Both are
# about the file's own name rather than anything inside it, so neither needs an
# AST; they read `path` and ignore `source`.
#
# laws.yml#beauty already asks for `meaningful_names_intention_revealing` and
# `kanso: eliminate_essence`. Nothing enforced either on a filename, and the
# 2026-08-31 session produced capture_final2.rb, capture_final3.rb and
# frames_final2/ in one sitting — names that record the order they were made in
# and throw away the thing that actually differed (a keep-alive, then trusted
# input).
        # A sequence word is a timestamp wearing a name. If two files differ,
        # the name says how; if it cannot, they are one file or the difference
        # is not yet understood.
        





























        # A category is not a thing. util/manager/handler name the shape of a box
        # rather than what is in it, so the next reader must open it. The words are
        # data/vague_words.yml, shared with the sprawl census, the rename sweep and
        # the slug filler; why base, common and shared are not among them is there.
        



















      end
    end
  end
end
