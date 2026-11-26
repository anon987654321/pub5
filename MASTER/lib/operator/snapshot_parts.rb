# frozen_string_literal: true

require "fileutils"
require_relative "snapshot_minify"
require_relative "snapshot_split"

module Operator

  # The full source of a tree for an external model: a file tree, then every tracked text file
  # whole, each framed as <file path="..." bytes="N"> ... </file>. The byte count frames the body,
  # so a file that itself contains "</file>" cannot end its block early. Parts follow the tree's
  # subsystems (MASTER/lib, MASTER/web, ...): small subsystems share a part, a large one fills parts
  # of its own, and a file larger than a part is cut by SnapshotSplit into blocks that rejoin byte
  # for byte. Every part opens with the same header and tree, so one part alone says where the rest are.
  #
  # Two variants: the exact source, and the code variant that SnapshotMinify has stripped of comments.
  module SnapshotParts
    # About 875K tokens: one part fits a 1M-context model with room to answer. --part-bytes or
    # MASTER_SNAPSHOT_PART_BYTES changes it; a pack is never truncated, only split.
    DEFAULT_PART_BYTES = 3_500_000
    # Open and close tags around a block's body.
    BLOCK_OVERHEAD = 400
    # A part this small has no room for source once the tree is paid for.
    MIN_ROOM = 1_000
    # A big file starts in the room left in a part only when that is at least this fraction of a part.
    MIN_FILL = 4
    VARIANTS = %i[exact code].freeze
    TESTS_LEFT_OUT = "test, --no-tests"

    Unit = Struct.new(:path, :text, keyword_init: true)
    # One run: the host's tree in one variant, cut into parts of part_bytes, with or without tests.
    Job = Struct.new(:host, :tree, :variant, :part_bytes, :tests, :part_count, keyword_init: true)
    # What the run packed: the files, what it left out and why, and the revision.
    Packed = Struct.new(:job, :files, :omitted, :sha, keyword_init: true)
    # Where one block of a file cut across blocks sits.
    Span = Struct.new(:index, :total, :first_line, keyword_init: true)

    # Fills parts in order: a unit that would overflow the current part opens the next one.
    class Filler
      attr_reader :parts, :room

      def initialize(room)
        @room = room
        @parts = [[]]
        @used = 0
      end

      def left = @room - @used

      def fits?(size) = @used + size <= @room

      def next_part!
        @parts << [] if @used.positive?
        @used = 0
      end

      def add(unit)
        next_part! unless fits?(unit.text.bytesize)
        @parts.last << unit
        @used += unit.text.bytesize
      end

      # A file that fits the room left goes whole; one larger than a whole part starts in the room
      # left when that is worth having; anything else starts a fresh part.
      def place(file)
        size = file[:block].bytesize
        whole = [Unit.new(path: file[:path], text: file[:block])]
        units = if size <= left then whole
                elsif size > @room && left >= @room / MIN_FILL then SnapshotParts.pieces(file, @room, left)
                end
        unless units
          next_part!
          units = size <= @room ? whole : SnapshotParts.pieces(file, @room, @room)
        end
        units.each { |unit| add(unit) }
      end
    end

    module_function

    # snapshot_T.md, or snapshot_T.part01-of-03.md; the code variant adds ".code" after the tree.
    def file_names(tree, variant, count)
      base = variant == :code ? "snapshot_#{tree}.code" : "snapshot_#{tree}"
      return ["#{base}.md"] if count == 1

      width = [2, count.to_s.size].max
      (1..count).map { |k| "#{base}.part#{k.to_s.rjust(width, '0')}-of-#{count.to_s.rjust(width, '0')}.md" }
    end

    # Where the host writes snapshots; a host without OUTPUT_DIR writes beside its sources.
    def out_dir(host) = host.const_defined?(:OUTPUT_DIR) ? host::OUTPUT_DIR : host::REPO

    # Every snapshot file the tree has in the output directory: single, parts, either variant.
    def stale_pattern(tree) = /\Asnapshot_#{Regexp.escape(tree)}(\.code)?(\.part\d+(-of-\d+)?)?\.md\z/

    def attr(value) = value.to_s.gsub("&", "&amp;").gsub('"', "&quot;")

    # One block. A body without a final newline gets one for framing and says so with eol="none".
    def block(path, body, span = nil)
      open_ended = !body.empty? && !body.end_with?("\n")
      tag = +%(<file path="#{attr(path)}")
      tag << span_attrs(body, span) if span
      tag << %( eol="none") if open_ended
      "#{tag} bytes=\"#{body.bytesize}\">\n#{body}#{"\n" if open_ended}</file>\n\n"
    end

    def span_attrs(body, span)
      last = span.first_line + body.count("\n") - (body.end_with?("\n") || body.empty? ? 1 : 0)
      %( part="#{span.index}/#{span.total}" lines="#{span.first_line}-#{last}")
    end

    # Readable text files, split into those packed and those named as left out. Binary files are counted.
    def collect(job, paths)
      entries = []
      omitted = Hash.new { |hash, key| hash[key] = [] }
      paths.each do |path|
        absolute = File.join(job.host::REPO, path)
        next unless File.file?(absolute)

        reason = omission(job, path)
        next omitted[reason] << path if reason

        text = File.binread(absolute).force_encoding(Encoding::UTF_8)
        next omitted["not valid UTF-8"] << path unless text.valid_encoding?

        entries << entry(path, text, job.variant)
      end
      [SnapshotPack.rank_centrality(entries), omitted]
    end

    def omission(job, path)
      return "binary" if job.host.binary?(File.join(job.host::REPO, path))

      SnapshotPack.omit_reason(path) || (TESTS_LEFT_OUT if !job.tests && SnapshotPack.test_path?(path))
    end

    def entry(path, text, variant)
      code = SnapshotMinify.call(path, text)
      body = variant == :code ? code : text

      { path:, original: text, minified: code, body:, block: block(path, body) }
    end

    # MASTER/lib/x.rb belongs to MASTER/lib; a file at the top of the tree to the tree itself.
    def subsystem(path)
      segments = path.split("/")
      segments.size > 2 ? segments.first(2).join("/") : segments.first
    end

    # Subsystems in reading order (the one holding the constitution and entry points first), each
    # with its files in reading order.
    def subsystems(entries)
      groups = entries.group_by { |f| subsystem(f[:path]) }
      groups.transform_values! { |files| files.sort_by { |f| SnapshotPack.reading_order(f) } }
      groups.sort_by { |name, files| [SnapshotPack.reading_order(files.first).first, name] }
    end

    # The pieces of one file: one block when it fits, else consecutive blocks cut at SnapshotSplit
    # boundaries, the first sized to the room left in the part it starts in.
    def pieces(file, room, left)
      cut = SnapshotSplit.chunks(file[:path], file[:body], room - BLOCK_OVERHEAD, first: left - BLOCK_OVERHEAD)
      line = 1
      cut.each_with_index.map do |piece, i|
        text = block(file[:path], piece, Span.new(index: i + 1, total: cut.size, first_line: line))
        line += piece.count("\n") + (piece.end_with?("\n") || piece.empty? ? 0 : 1)
        Unit.new(path: file[:path], text:)
      end
    end

    # A subsystem starts a new part when it would not fit in the room left; small ones share.
    def assign(groups, room)
      filler = Filler.new(room)
      groups.each do |_name, files|
        filler.next_part! unless filler.fits?(files.sum { |f| f[:block].bytesize })
        files.each { |file| filler.place(file) }
      end
      filler.parts
    end

    def part_tag(spans, key, width)
      first, last = spans.fetch(key, []).minmax
      return "" unless first

      one = "p#{first.to_s.rjust(width, '0')}"
      first == last ? " [#{one}]" : " [#{one}-#{last.to_s.rjust(width, '0')}]"
    end

    # The tracked files as an indented tree, directories ending in "/". Binary files are listed
    # and marked; other left-out files are named under the tree. With more than one part, each
    # subsystem directory says which part holds it.
    def tree_text(paths, binaries, spans: {}, width: 2)
      printed = Set.new
      (paths + binaries).uniq.sort.each_with_object(+"") do |path, out|
        dirs = path.split("/")[0...-1]
        out << dir_lines(dirs, printed, spans:, width:)
        out << "#{'  ' * dirs.size}#{File.basename(path)}#{' (binary)' if binaries.include?(path)}\n"
      end
    end

    def dir_lines(dirs, printed, spans:, width:)
      lines = dirs.each_index.filter_map do |depth|
        key = dirs[0..depth].join("/")
        next unless printed.add?(key)

        "#{'  ' * depth}#{dirs[depth]}/#{part_tag(spans, key, width) if depth <= 1}\n"
      end
      lines.join
    end

    def omitted_lines(omitted)
      listed = omitted.reject { |reason, _| reason == "binary" }.sort
      return "" if listed.empty?

      "\n#{listed.flat_map { |reason, list| list.sort.map { |p| "left out (#{reason}): #{p}" } }.join("\n")}\n"
    end

    GUIDE = "The Tree lists every tracked file; each text file then appears once, whole, between " \
            '<file path="..." bytes="N"> and </file>, where N is the exact byte length of the body. ' \
            "A file larger than a part is cut between top-level constructs into blocks marked " \
            'part="k/m" lines="a-b"; join them in order, adding nothing, to get the file byte for byte. ' \
            'eol="none" marks a file without a final newline. Nothing is truncated or summarised.'
    STRIPPED = " Comments and blank lines are removed (a file's first comment stays as one purpose line); " \
               "nothing else changes."

    def guide(job, count)
      kind = job.variant == :code ? "code-only" : "exact"
      shape = count == 1 ? "one file" : "#{count} parts cut at subsystem boundaries"
      "Reading guide: the #{kind} source of the #{job.tree} tree in #{shape}. #{GUIDE}" \
        "#{STRIPPED if job.variant == :code} Generated files, binaries and dependency trees are named, not inlined."
    end

    def title(tree, part:, count:)
      width = [2, count.to_s.size].max
      "# #{tree} - source snapshot, part #{part.to_s.rjust(width, '0')} of #{count.to_s.rjust(width, '0')}\n\n"
    end

    def pack_line(packed, part:, count:)
      job = packed.job
      "Pack: tree=#{job.tree} git=#{packed.sha} part=#{part}/#{count} variant=#{job.variant} " \
        "files=#{packed.files.size} omitted=#{packed.omitted.values.sum(&:size)} " \
        "tests=#{job.tests ? 'yes' : 'no'} budget=full\n\n"
    end

    # Identical in every part but the part line.
    def header(packed, part, count, tree_map)
      "#{title(packed.job.tree, part:, count:)}#{pack_line(packed, part:, count:)}#{guide(packed.job, count)}\n\n" \
        "#{SnapshotPack.omitted_note(packed.omitted)}## Tree\n\n#{tree_map}#{omitted_lines(packed.omitted)}\n" \
        "## Source (part #{part} of #{count})\n\n"
    end

    # The parts in memory: [[file name, text] ...]. Raises when the part size leaves no room for source.
    def build(job, paths)
      files, omitted = collect(job, paths)
      packed = Packed.new(job:, files:, omitted:, sha: job.host.head_sha)
      render(packed, assign(subsystems(files), room(packed)))
    end

    # The part size less the widest header any part can carry.
    def room(packed)
      widest = header(packed, 99, 99, tree_map(packed, widest_spans(packed)))
      room = packed.job.part_bytes - widest.bytesize
      return room if room >= MIN_ROOM

      raise "snapshot: #{packed.job.tree} part size #{packed.job.part_bytes} leaves no room after the tree"
    end

    # Every subsystem tagged with the widest part range, to measure the tree before the cut is known.
    def widest_spans(packed)
      paths = packed.files.map { |f| f[:path] } + packed.omitted["binary"]
      paths.flat_map { |p| [subsystem(p), p.split("/").first] }.to_h { |k| [k, [98, 99]] }
    end

    def tree_map(packed, spans, width: 2)
      tree_text(packed.files.map { |f| f[:path] }, packed.omitted["binary"], spans:, width:)
    end

    def render(packed, parts)
      count = packed.job.part_count = parts.size
      names = file_names(packed.job.tree, packed.job.variant, count)
      map = tree_map(packed, count > 1 ? spans(parts) : {}, width: [2, count.to_s.size].max)
      parts.each_with_index.map { |units, i| [names[i], part_text(packed, units, part: i + 1, map:)] }
    end

    def part_text(packed, units, part:, map:)
      count = packed.job.part_count
      "#{header(packed, part, count, map)}#{units.map(&:text).join}## End of part #{part} of #{count}\n"
    end

    # Which parts hold each subsystem and the tree's top: {"MASTER/lib" => [3, 4], "MASTER" => [1]}.
    def spans(parts)
      spans = Hash.new { |hash, key| hash[key] = [] }
      parts.each_with_index do |units, i|
        units.each { |unit| spans[subsystem(unit.path)] << i + 1 }
      end
      spans
    end

    def write(job, paths:, io: $stdout)
      dir = out_dir(job.host)
      build(job, paths).map do |name, text|
        File.write(File.join(dir, name), text, encoding: "UTF-8")
        size = text.bytesize
        Master::Trace::Dmesg.status("snapshot0", "#{job.tree}, #{name}, #{size} bytes (~#{size / 4000}K tokens)", io:)
        File.join(dir, name)
      end
    end
  end
end
