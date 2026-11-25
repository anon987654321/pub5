# frozen_string_literal: true

require "pathname"

module Master
  module Fix
    class Restructure
      # RADICAL_STRUCTURE's pack mode: finds single-file directories (a
      # directory holding exactly one file and no subdirectory) and renders
      # the Restructure plan that packs each file into its existing parent
      # namespace file - the move the sprawl census calls repaying lone_dirs,
      # authorized by the operator as a radical session (soul.yml,
      # radical_sessions). Planning only: the Restructure engine still owns
      # validation, hostile review, proofs and rollback, and the plan names
      # the merge operation so TransformationPlan keeps its constitutional
      # order.
      #
      # A candidate is packed, not merged: the child's full module/class
      # chain is stripped and its body is appended inside the parent file's
      # own chain, before the parent's closing ends, so the nested constant
      # keeps its name and Zeitwerk keeps mapping the parent file to the
      # parent constant. A require_relative of the destination itself is
      # dropped; every other one loses one leading "../", because the file
      # moves one directory up. A candidate is skipped, never half-moved,
      # when the convention it would rely on does not hold: a child chain
      # that does not extend the parent's chain, a parent that does not
      # close its chain at the end of the file, or a remaining reference to
      # the child path anywhere else in the scanned tree.
      module PackPlan
        module_function

        Candidate = Data.define(:dir, :file, :parent_file, :packed_body) do
          def child_name = file.basename.sub_ext("").to_s
        end

        HEADER = /\A\s*(?:module|class) [A-Z][A-Za-z0-9_]*\n\z/

        # Every single-file directory under scan_root whose sibling parent
        # file <name>.rb exists and whose layout the pack convention holds
        # for. Skipped candidates are absent from the result.
        def candidates(scan_root)
          scan_root = Pathname.new(scan_root.to_s)
          scan_root.glob("**/*/").filter_map { |dir| candidate_for(scan_root, dir) }
        end

        # One single-file directory's Candidate, or nil: the parent file
        # must exist, the pack convention must hold, and nothing outside
        # the pair may still require the child.
        def candidate_for(scan_root, dir)
          child = lone_file(dir)
          return unless child

          parent = dir.dirname.join("#{dir.basename}.rb")
          return unless parent.file?

          pair = Pair.new(parent_file: parent, child_file: child, dir_name: dir.basename.to_s)
          packed = packed_parent_body(pair)
          return unless packed

          return if referenced?(scan_root, pair.dir_name, pair.child_file, pair.parent_file)

          Candidate.new(dir, pair.child_file, pair.parent_file, packed)
        end

        # The one file of a directory holding exactly one file and no
        # subdirectory, or nil.
        def lone_file(dir)
          files = dir.children.select(&:file?)
          files.fetch(0) if files.size == 1 && dir.children.none?(&:directory?)
        end

        # One Restructure plan per candidate, with paths named from
        # plan_root: the engine allows one explicit delete per restructure,
        # so each pack travels alone. Empty when nothing qualifies.
        def plans(plan_root:, scan_root:)
          candidates(scan_root).map { |candidate| plan_text(plan_root:, scan_root:, candidate:) }
        end

        # The Restructure plan text for one candidate (the first by
        # default), or nil when nothing qualifies.
        def plan_text(plan_root:, scan_root:, candidate: nil)
          candidate ||= candidates(scan_root).first
          return unless candidate

          root = Pathname.new(plan_root.to_s)
          <<~PLAN
            SUMMARY: Pack #{candidate.child_name} into #{candidate.parent_file.basename}
            OPERATIONS: merge
            #{write_entry(root, candidate)}
            #{delete_entry(root, candidate)}
          PLAN
        end

        def write_entry(plan_root, candidate)
          "=== WRITE #{candidate.parent_file.relative_path_from(plan_root)}\n#{candidate.packed_body}"
        end

        def delete_entry(plan_root, candidate)
          "=== DELETE #{candidate.file.relative_path_from(plan_root)}"
        end

        # The parent file's body with the child appended inside its chain,
        # or nil when the convention does not hold for the pair. The child
        # keeps everything the parent chain does not already name: its
        # header, the suffix of its chain below the common prefix, its body
        # and that suffix's own ends. A child opening exactly the parent
        # chain contributes its body alone.
        ChildParts = Data.define(:header, :suffix_chain, :body, :kept_ends)

        # The pack's subject: one child file, the parent namespace file that
        # will absorb it, and the single-file directory that joins them.
        Pair = Data.define(:parent_file, :child_file, :dir_name) do
          def needle = "#{dir_name}/#{child_file.basename.sub_ext('')}"
        end

        def packed_parent_body(pair)
          parent_header = chain_header(pair.parent_file)
          child_header = chain_header(pair.child_file)
          return unless parent_header && child_header

          depth = agreed_chain_depth(parent_header, child_header)
          return unless depth

          parent_lines = pair.parent_file.read.lines
          tail = parent_closing_tail(parent_lines, depth)
          return unless tail

          parts = child_parts(child_file: pair.child_file, child_header:, parent_depth: depth)
          return unless parts

          head = packed_parent_head(pair:, parent_header:, parent_lines:, parts:)
          "#{head.join}#{parent_lines.join.sub(/\n\z/, '')}\n\n#{inner_body(parts)}#{tail.join}"
        end

        # The parent's head region: everything before its chain, with the
        # child's requires moved in and the parent's own require of the
        # deleted child dropped.
        def packed_parent_head(pair:, parent_header:, parent_lines:, parts:)
          head = parent_lines.shift(parent_header.fetch(:start))
          head = without_parent_require_of_child(head, pair)
          with_moved_requires(head, child_requires(parts.header, pair.parent_file))
        end

        # The common chain depth the pack relies on: the child's chain must
        # extend the parent's, and the parent's must not be empty. Nil when
        # they disagree.
        def agreed_chain_depth(parent_header, child_header)
          parent_chain = parent_header.fetch(:chain)
          child_chain = child_header.fetch(:chain)
          depth = parent_chain.size

          return if depth.zero? || child_chain.size < depth
          return unless child_chain.first(depth) == parent_chain

          depth
        end

        def parent_closing_tail(parent_lines, depth)
          tail = parent_lines.pop(depth)

          tail if tail.all? { |line| line.strip == "end" }
        end

        # The child's lines split for packing: its require header, the chain
        # below the common prefix with the parent, the body between the
        # chains, and that suffix's own ends. Nil when the trailing ends do
        # not close the chain.
        def child_parts(child_file:, child_header:, parent_depth:)
          child_lines = child_file.read.lines
          start = child_header.fetch(:start)
          child_depth = child_header.fetch(:chain).size
          ends = closing_ends(child_lines, child_depth)
          return unless ends

          split_child(child_lines:, child_header:, parent_depth:, ends:)
        end

        # Pops the chain's trailing ends, or nil when the file does not end
        # on exactly that many `end` lines.
        def closing_ends(child_lines, child_depth)
          ends = child_lines.pop(child_depth)

          return unless ends.all? { |line| line.strip == "end" }

          ends
        end

        def split_child(child_lines:, child_header:, parent_depth:, ends:)
          start = child_header.fetch(:start)
          kept = child_header.fetch(:chain).size - parent_depth
          # The trailing ends close the chain innermost first, so the
          # suffix's own ends lead the list.
          kept_ends = ends.shift(kept)
          suffix_chain = child_lines.slice!(start + parent_depth, kept)
          body = child_lines.slice!(start + parent_depth, child_lines.size - start - parent_depth)
          header = child_lines.shift(start)
          ChildParts.new(header, suffix_chain, body, kept_ends)
        end

        # The child's require_relative lines move into the parent's own
        # header region: one directory up, and a require of the destination
        # itself is dropped - after packing it would point at the file it
        # already lives in. The rest of the child header (frozen-string
        # comment, blanks) belongs to the file, not the constant, and is not
        # carried over.
        def child_requires(header, parent_file)
          header.grep(/\Arequire_relative "/)
                .filter_map { |line| rewritten_child_require(line, parent_file) }
        end

        def inner_body(parts)
          inner = (parts.suffix_chain + parts.body + parts.kept_ends).join
          inner.gsub(/\n{3,}/, "\n\n").sub(/\A\n+/, "").sub(/\n*\z/, "\n")
        end

        # The parent's own require of the child names a file this pack
        # deletes; the packed constant lives here now.
        def without_parent_require_of_child(head, pair)
          head.reject { |line| line.match?(/^require_relative "[^"]*#{Regexp.escape(pair.needle)}(\.rb)?"$/) }
        end

        def with_moved_requires(head, moved_requires)
          return head if moved_requires.empty?
          head.join.rstrip.lines + moved_requires + ["\n"]
        end

        # One directory up: a require_relative loses its leading "../", and
        # one that resolved to the destination file itself returns nil -
        # after packing it would point at the file it already lives in.
        def rewritten_child_require(line, parent_file)
          line.sub(/^require_relative "(.*)"$/) do
            stripped = Regexp.last_match(1).sub(/\A\.\.\//, "")
            return if stripped == parent_file.basename.sub_ext("").to_s
            "require_relative \"#{stripped}\""
          end
        end

        # The leading module/class chain of a file, after its comment and
        # require header, as plain constant names. Nil when the file never
        # opens one.
        def chain_header(file)
          lines = file.read.lines
          start = lines.index { |line| line.match?(HEADER) }
          return if start.nil?
          chain = lines[start..].take_while { |line| line.match?(HEADER) }
          { chain: chain.map { |line| line.strip.sub(/\A(?:module|class) /, "").chomp }, start: }
        end

        # Whether any file other than the pair still names the child's
        # require path - a leftover require would break the moment the file
        # moves. The needle is the path fragment a require_relative of the
        # child must contain ("boot_sound/dsp"), not the bare basename,
        # which any prose may carry.
        def referenced?(scan_root, dir_name, child_file, parent_file)
          needle = "#{dir_name}/#{child_file.basename.sub_ext('')}"
          Pathname.new(scan_root.to_s).glob("**/*.rb").each do |file|
            next if file == child_file || file == parent_file
            return true if file.read.include?(needle)
          end
          false
        end
      end
    end
  end
end
