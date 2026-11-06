# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/ruby.rb (shared code; its Law.define calls moved to laws/pub4/) by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: d2e8938ec4ceabe2
require_relative "../lib/master"

# External practice sources represented here are deliberate inputs, not a second authority:
# RuboCop Ruby Style Guide (live guide); RuboCop Rails Style Guide; Fowler, Refactoring, 2nd ed. (2018);
# Martin, Clean Code, 2nd ed. (2025); Evans, Polished Ruby Programming, 2nd ed. (2026, Ruby 4.0).
# Mechanical style belongs to RuboCop; these Laws cover project-specific semantics, safety and refactoring proof.
# law/ruby.rb — every ruby law, one Law.define per law.








# FEW_ARGUMENTS lives once, in the registry (universal_laws.rb): it splits
# the parameter list and counts only positionals, where this regex counted
# keywords, defaults, splats and blocks as arguments too — a def with four
# keyword args is the fix, not the offence. KEYWORD_ARGS folds into it: two
# ids counted the same parameter list, one at :warn and one at :info, so the
# same def carried two findings that differed only in name.
























































































# HASH_FETCH lives once, in the registry (ruby_laws.rb): it excludes
# memoization (`||=`), the string-or-symbol dual-key fallback in either key
# order, and comparison chains that merely contain a bracket access — none
# of which are fetch candidates, all of which this bare regex flagged.



























# KEYWORD_ARGS was deleted here on 2026-08-21 — folded into FEW_ARGUMENTS
# (see that entry above): two ids, one detector concept, double findings.

# law/rails.rb was deleted here on 2026-08-21. Its four rules — FIND_EACH,
# N_PLUS_ONE, NO_UPDATE_ATTRIBUTE, PLUCK_OVER_MAP — declared `languages
# %i[rails]`, and FILE_LANGUAGE_MAP produces no such language: every .rb
# file is "ruby". The four laws had never matched a single file; the
# registry twins (ruby_laws.rb, universal_laws.rb), path-scoped to
# /app/, were the only live implementations all along — the inert-config
# defect, in the constitution itself. They live once, in the registry.































































































































































































#
# The reason it was left semantic is the exception, not the rule: a constant
# holding a *type* is CamelCase by convention — Entry = Data.define(...),
# Finding = Struct.new(...) — and this tree uses that shape everywhere. So the
# detector asks what is on the right, not only what is on the left, and an
# alias of another constant is spared for the same reason.















# RUBY_TERNARY_NOT_NESTED lives once, in the registry (cosmetic_laws.rb):
# it parses with Prism and asks the AST whether a ternary branch holds a
# ternary. This regex counted `?` and `:` characters, so a string literal
# containing a question mark or a hash colon made any ternary "nested".































































































# Polished Ruby Programming (Jeremy Evans), ch. 1-2: reopening a core class
# changes it for every library in the process — the least polite thing a
# codebase can do. A refinement or a helper module carries the same behaviour
# without the blast radius.








# Clean Code — a class name is a noun that carries domain meaning. The
# deterministic floor under DOMAIN_LANGUAGE and LOAD_BEARING_NAMES, which
# otherwise only a model judges: a class or module named nothing but a noise
# word says only that code lives here, which the file already said. Bare names
# only — a domain qualifier redeems it, so UserManager and PaymentHelper pass
# and only standalone Manager, Utils, Misc do not. :info, narrow on purpose,
# because naming rules earn their width by not crying wolf.










# Polished Ruby Programming: __dir__ is the modern spelling and survives
# symlinks the way the old idiom does not.








# New (2026-09-17, book research). Fowler's Replace Loop with Pipeline:
# map-then-compact is two passes and a nil detour to say "give me the present
# values"; filter_map says it in one. RuboCop's Style/MapCompactWithFilterMap
# is disabled in both this tree's config and the omakase one, so nothing else
# flags it, and live sites existed in wardrobe_ai.rb and lib/trace at the time
# this landed. Only the single-line spelling: a map block spanning lines with
# .compact on its own line is invisible to a line detector, and chasing it
# costs more noise than the finding is worth.










# New (2026-09-17, book research). Kleppmann: a stalled peer stalls you. An
# outbound HTTP call with no timeout hangs indefinitely on a silent peer, and
# on a 1-vCPU vm23 that is the box's signature outage shape — a hang, not a
# 5xx. DEGRADE_GRACEFULLY declared the principle with no timeout-shaped
# detector; this is one. File-scoped on purpose: `http = Net::HTTP.new(...)`
# followed by `http.open_timeout = 5` on its own line is the disciplined
# spelling a line detector would flag, so the question asked is whether the
# FILE ever names a timeout at all. A file naming one for a different call
# covers its HTTP too — a narrowing, recorded here, that keeps the honest
# idioms quiet.












# New (2026-09-17, book research). A NOT NULL column added with no default
# breaks the previous code version during a rolling deploy: every insert
# between the migrate and the restart fails, and on this box a deploy already
# sheds amber and bsdports. The tree carried zero violations when this landed
# — every null: false had its default — so this is a guard on the exact shape
# of the most expensive failure class the deploys have, in the role
# MIGRATION_ADD_REFERENCE_NO_FK plays for references. add_column only:
# change_column_null is constrained after a backfill that lives in an earlier
# migration file, invisible from here, and flagging every one of those would
# cry wolf until the rule was ignored.











module Master
  module Review
    module Scan
      module Laws

        # Assignment/branch/condition counts for one method, for ABC size.
        #
        # A module method rather than a lambda inside the rule block: counting
        # them in place put the case arms five levels deep — rule block, walk
        # lambda, def check, inner lambda, case — and LINEARITY caps nesting at
        # four. The rule that reported it is defined in this file, so the file
        # was failing the law it declares.
        #
        # Flat here on purpose: one guard, one dispatch to a lookup, no nesting
        # to reintroduce.
        module RubyRuleSupport
          ASSIGNMENT_NODES = %i[
            LocalVariableWriteNode InstanceVariableWriteNode ClassVariableWriteNode
            GlobalVariableWriteNode ConstantWriteNode LocalVariableOperatorWriteNode
            InstanceVariableOperatorWriteNode MultiWriteNode
          ].freeze

          CONDITION_NODES = %i[
            IfNode UnlessNode WhileNode UntilNode CaseNode WhenNode AndNode OrNode RescueNode
          ].freeze

          # [assignments, branches, conditions] over the whole subtree.
          def self.abc_counts(node)
            counts = { a: 0, b: 0, c: 0 }
            visit(node, counts)
            [counts[:a], counts[:b], counts[:c]]
          end

          def self.visit(node, counts)
            node.child_nodes.compact.each do |child|
              next unless child.respond_to?(:child_nodes)

              counts[bucket(child)] += 1 if bucket(child)
              visit(child, counts)
            end
          end

          # A CallNode ending in `=` is an assignment, not a branch — attr
          # writers would otherwise inflate B for every setter call.
          def self.bucket(node)
            short = node.class.name.split("::").last.to_sym
            return :a if ASSIGNMENT_NODES.include?(short)
            return :c if CONDITION_NODES.include?(short)
            return unless short == :CallNode

            node.name.to_s.end_with?("=") ? :a : :b
          end

          # A multi-line array or hash whose last element is not followed by a
          # comma before the closing bracket. Percent literals are excluded
          # because %w[] and %i[] separate on whitespace, so a comma inside one
          # becomes part of an element.
          def self.unterminated_collection?(node, src)
            opening = node.opening_loc
            closing = node.closing_loc
            return false unless opening && closing && !node.elements.empty?
            return false if opening.slice.start_with?("%")

            last = node.elements.last.location
            return false unless last.end_line < closing.start_line
            # RuboCop's `comma` style wants no comma once two items share a line.
            return false if node.elements.each_cons(2).any? { |left, right| left.location.end_line == right.location.start_line }

            gap = src.byteslice(last.end_offset, closing.start_offset - last.end_offset).to_s
            !gap.sub(/#.*/, "").include?(",")
          end
        end

        # Retired registry twins — each lives once, in law/:
        #   MIGRATION_ADD_REFERENCE_NO_FK, MIGRATION_FIND_OR_CREATE_BY, MIGRATION_REMOVE_COLUMN, PERCENT_LITERAL
        #   RATE_LIMITING_MISSING, STRICT_LOADING_MISSING, TRANSFORM_KEYS
        # (test_scan_rule_contracts proves each reaches findings through the bridge).

        # SINGLE_PRIVATE_SECTION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # principle_map: strong_parameters (detects mass_assignment_risk). Two
        # distinct failures, one law: permit! waives the whitelist wholesale,
        # and a raw params[] reaching a mass-assignment sink never had one.
        # Scoped to /app/ rather than /app/controllers/ because a service or
        # model object handed the params hash carries the same risk.
        
















        # EACH_WITH_OBJECT lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        # KERNEL_COERCION lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        

























        # IMMUTABLE lives once, in law/ruby.rb — fixtures attached, any narrowing
        # this version had learned ported there (2026-08-21 twin retirement).

        











        










        














        # KEYWORD_ARGS was deleted here on 2026-08-21 — folded into FEW_ARGUMENTS
        # (universal_laws.rb): two ids counted the same parameter list, one at
        # :warn and one at :info, and every 3+-positional def carried both.

        



































        # ABC size, the one external-linter signal with no bespoke equivalent:
        # the 2026-08-13 overlap measurement (debt: scanner_overlaps_two_
        # installed_linters) found Metrics/AbcSize produced 13 of the 42
        # findings nothing here could see — the largest unique signal on
        # either side. Written bespoke per that entry's conclusion instead of
        # bridging rubocop per-file: sqrt(A²+B²+C²), counted from the AST,
        # never from line text, calibrated against rubocop on a shared file
        # (85.5 here vs 85.91 there for the same method).
        #
        # The THRESHOLD is the ratchet. At rubocop's default 17 the fleet
        # holds 560 findings — a flood that would bury the constitutional
        # ceilings recorded at 1/21/1/1 the same day. 40 catches the 24
        # worst (top: 85.5 in brgen's application_helper); walk it down as
        # they fall: 40 -> 30 (81) -> 25 (169) -> 17 (560).
        



























        # Only array and hash literals, because those are the two the autofix
        # `add_trailing_commas` closes on — it matches a line opening with `]`
        # or `}`. The lexical detector this replaces matched any line holding
        # nothing but a quoted string, so it reported 496 findings across MASTER
        # of which the great majority were a method's last expression or an
        # assertion message, and the fixer would have touched none of them.
        





















      end
    end
  end
end
