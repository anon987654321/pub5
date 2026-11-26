# frozen_string_literal: true

require "ripper"
require_relative "snapshot_minify"

module Operator

  # Reads the written snapshot parts back and proves them against the tree: every tracked text file
  # reassembled from its blocks must equal the file byte for byte (exact variant), or equal its
  # minified text and carry the same Ruby tokens (code variant). A file with no block and no
  # "left out" line is missing. It reads the parts from disk and the tree from git, and shares
  # nothing with the writer but the block format, so a writer that drops files cannot pass.
  module SnapshotVerify
    class Failed < StandardError; end

    OPEN_TAG = %r{<file path="([^"]*)"(?: part="(\d+)/(\d+)" lines="(\d+)-(\d+)")?( eol="none")? bytes="(\d+)">\n}n
    CLOSE_TAG = "</file>\n".b
    LEFT_OUT = /\Aleft out \(([^)]*)\): (.+)\n\z/
    PACK_LINE = %r{^Pack: tree=(\S+) git=(\S+) part=(\d+)/(\d+) variant=(\S+)}
    SHOWN = 8
    NOISE = %i[on_comment on_sp on_nl on_ignored_nl on_embdoc_beg on_embdoc on_embdoc_end].freeze

    module_function

    def call(host, tree, variant:, only: nil, io: $stdout)
      parts = read_parts(host, tree, variant)
      problems = []
      blocks, left_out = parse(parts, tree, variant, problems)
      expected = expected_files(host, tree, only, left_out, problems)
      missing = expected.keys - blocks.keys
      problems.concat(missing.first(SHOWN).map { |p| "missing: #{p}" })
      expected.each { |path, text| compare(path, text, blocks[path], variant, problems) if blocks.key?(path) }
      (blocks.keys - expected.keys).first(SHOWN).each { |p| problems << "not in the tree: #{p}" } unless only

      label = variant == :code ? "#{tree} code" : tree
      raise Failed, "snapshot0: #{label} FAILED, #{missing.size} missing, #{problems.size} problem(s)\n#{problems.first(SHOWN).join("\n")}" unless problems.empty?

      Master::Trace::Dmesg.status("snapshot0", "#{label} verified #{expected.size} files, #{missing.size} missing", io:)
      expected.size
    end

    def read_parts(host, tree, variant)
      out = SnapshotParts.out_dir(host)
      names = Dir.children(out).grep(SnapshotParts.stale_pattern(tree))
                 .select { |n| n.include?(".code") == (variant == :code) }
      raise Failed, "snapshot0: #{tree} #{variant} has no snapshot files to verify" if names.empty?

      names.sort.map { |name| [name, File.read(File.join(out, name), encoding: "UTF-8")] }
    end

    # blocks: path => [[index, total, from, to, body]]; left_out: path => the reason the header gives.
    def parse(parts, tree, variant, problems)
      blocks = Hash.new { |hash, key| hash[key] = [] }
      left_out = {}
      seen = []

      parts.each do |name, text|
        meta = text.match(PACK_LINE)
        if meta && meta[1] == tree && meta[5] == variant.to_s
          seen << meta[3].to_i
          problems << "#{name}: expects #{meta[4]} parts, found #{parts.size}" if meta[4].to_i != parts.size
        else
          problems << "#{name}: no Pack line for #{tree} #{variant}"
        end
        read_blocks(name, text, blocks, left_out, problems)
      end

      problems << "parts present #{seen.sort.inspect}, expected 1..#{parts.size}" unless seen.sort == (1..parts.size).to_a
      [blocks, left_out]
    end

    # Blocks are read by their byte count, never by searching for the close tag, so a body that
    # contains "</file>" is read whole. eol="none" adds one framing newline after the body.
    def read_blocks(name, text, blocks, left_out, problems)
      src = text.b
      pos = src.index("## Source") || src.bytesize
      preamble = src.byteslice(0, pos).force_encoding(Encoding::UTF_8)
      preamble.each_line { |l| (m = l.match(LEFT_OUT)) && left_out[m[2]] = m[1] }

      while (tag = OPEN_TAG.match(src, pos))
        path = unescape(tag[1])
        size = tag[7].to_i
        body = src.byteslice(tag.end(0), size).force_encoding(Encoding::UTF_8)
        after = tag.end(0) + size + (tag[6] ? 1 : 0)
        unless body.bytesize == size && src.byteslice(after, CLOSE_TAG.bytesize) == CLOSE_TAG
          problems << "#{name}: block #{path} is not closed after #{size} bytes"
          break
        end

        blocks[path] << [(tag[2] || 1).to_i, (tag[3] || 1).to_i, tag[4].to_i, tag[5].to_i, body]
        pos = after + CLOSE_TAG.bytesize
      end
    end

    def unescape(value) = value.dup.force_encoding(Encoding::UTF_8).gsub("&quot;", '"').gsub("&amp;", "&")

    # Tracked text files the pack should hold: the tree's own record, not the writer's. A file the
    # header names as left out must be one the policy leaves out, or not text.
    def expected_files(host, tree, only, left_out, problems)
      files = {}
      SnapshotPack.paths_for(host, tree, only:).each do |path|
        absolute = File.join(host::REPO, path)
        next unless File.file?(absolute) && !host.binary?(absolute)

        text = File.binread(absolute).force_encoding(Encoding::UTF_8)
        if left_out.key?(path)
          explained = allowed_out?(path, left_out[path]) || !text.valid_encoding?
          problems << "left out without a reason: #{path}" unless explained
        elsif text.valid_encoding?
          files[path] = text
        end
      end

      files
    end

    # The policy leaves the path out, or the header left it out as a test under --no-tests.
    def allowed_out?(path, reason)
      SnapshotPack.omit_reason(path) || (reason == SnapshotParts::TESTS_LEFT_OUT && SnapshotPack.test_path?(path))
    end

    def compare(path, original, pieces, variant, problems)
      sorted = pieces.sort_by(&:first)
      total = sorted.first[1]
      problems << "#{path}: #{sorted.size} blocks of #{total} announced" unless sorted.size == total && sorted.map(&:first) == (1..total).to_a
      problems << "#{path}: line ranges do not follow one another" unless contiguous?(sorted)
      joined = sorted.map(&:last).join
      want = variant == :code ? SnapshotMinify.call(path, original) : original
      return problems << mismatch(path, want, joined) unless joined == want

      problems << "#{path}: Ruby tokens differ from the source" if variant == :code && ruby?(path) && tokens(original) != tokens(joined)
    end

    def contiguous?(sorted)
      return true if sorted.size == 1

      sorted.each_cons(2).all? { |a, b| b[2] == a[3] + 1 }
    end

    def ruby?(path) = SnapshotMinify::HANDLERS[File.extname(path).downcase] == :ruby

    def tokens(source)
      Ripper.lex(source).reject { |_, type, _, _| NOISE.include?(type) }.map { |_, type, tok, _| [type, tok.strip] }.reject { |_, tok| tok.empty? }
    rescue StandardError
      nil
    end

    def mismatch(path, want, got)
      at = (0...[want.bytesize, got.bytesize].min).find { |i| want.getbyte(i) != got.getbyte(i) } || [want.bytesize, got.bytesize].min
      "#{path}: differs at byte #{at} (source #{want.bytesize} bytes, pack #{got.bytesize}) near #{want.byteslice([at - 20, 0].max, 60).inspect}"
    end
  end
end
