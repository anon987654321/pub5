#!/usr/bin/env ruby
# frozen_string_literal: true

# The G1 shape, generalized: a stamp file the chain READS as a trust gate but
# nothing WRITES is a check that silently never runs. .pub5-build-sha had five
# readers and zero writers; this audit asks that question of every stamp-like
# literal in a tree, so the shape can never regrow unnoticed.
#
#   ruby MASTER/tools/attestation_audit.rb [ROOT]
#
# Method: collect quoted path literals whose basenames look attestation-ish
# (stamp/manifest/receipt/attestation/build-sha/preflight), follow the shell
# variables they are assigned to ($asset_stamp mentions attribute to
# ".pub5-build-sha"), then classify every mention as a read guard
# (-f/-s/-e, File.exist?, File.read, source, cat) or a write (output
# redirect, File.write/binwrite, cp/install/mv/touch/tee, atomic_write).
# A literal with readers and no writer is reported. The report says "no
# writer found", not "unwritable" - a human rules on each row.

require "find"
require "json"

module AttestationAudit
  STAMP_NAME = /(?:stamp|manifest|receipt|attestation|build[-_]sha|preflight)/i.freeze
  SOURCE_EXT = /\A\.(?:sh|ksh|zsh|rb|py|js|mjs|yml|yaml)\z/.freeze
  SKIP_DIRS = %w[.git node_modules tmp log vendor].freeze
  # A candidate must look like a path, not a message: carries a directory
  # separator, is dotfile-shaped, or ends in a file extension. This filters
  # error-message literals ("no attestation") out of the candidate set.
  PATHISH = %r{(?:/|\A\.[^\s]|[.\s\w-]\.[A-Za-z0-9]{1,8}\s*\z)}.freeze
  ASSIGN_RE = /\b([A-Za-z_]\w*)=(?:"[^"\n]*"|\S+)/.freeze
  READ_RE = /\[\[?\s+-[fesr]\b|\bFile\.(?:exist\?|file\?|read|binread|size)\b|\bsource\b|\bcat\b/.freeze
  WRITE_RE = />>?|\bFile\.(?:write|binwrite)\b|\b(?:cp|install|mv|touch|tee|ln)\b|\batomic_write\b/.freeze

  module_function

  def source_files(root)
    files = []
    Find.find(root) do |path|
      base = File.basename(path)
      if File.directory?(path)
        Find.prune if SKIP_DIRS.include?(base) || base.start_with?(".")
        next
      end
      ext = File.extname(path)
      files << path if SOURCE_EXT.match?(ext) || (ext.empty? && File.executable?(path))
    rescue SystemCallError
      next
    end
    files
  end

  # literal => { mentions: [...], vars: [shell variable names bound to it] }
  def collect(root)
    literals = Hash.new { |h, k| h[k] = [] }
    vars = Hash.new { |h, k| h[k] = [] }
    source_files(root).each do |path|
      rel = path.delete_prefix("#{root}/")
      File.readlines(path, encoding: Encoding::UTF_8, invalid: :replace).each_with_index do |line, idx|
        line.scan(/["']([^"'\n]{2,120})["']/) do |(lit)|
          next unless STAMP_NAME.match?(File.basename(lit)) && PATHISH.match?(lit)

          literals[lit] << { at: "#{rel}:#{idx + 1}", text: line.strip }
          line.scan(ASSIGN_RE) { |(name)| vars[lit] << name if line.include?("#{name}=") && line.index(lit) > line.index("#{name}=") }
        end
      rescue ArgumentError
        next
      end
    end
    { literals:, vars: }
  end

  # Every line touching the literal or one of its bound variables, classified.
  def audit(root)
    data = collect(root)
    rows = data[:literals].map do |lit, mentions|
      names = data[:vars][lit].uniq
      var_re = names.empty? ? nil : Regexp.union(names.map { |n| /\$\{?#{n}\}?/ })
      lines = []
      source_files(root).each do |path|
        rel = path.delete_prefix("#{root}/")
        File.readlines(path, encoding: Encoding::UTF_8, invalid: :replace).each_with_index do |line, idx|
          next unless line.include?(lit) || (var_re && line.match?(var_re))

          lines << { at: "#{rel}:#{idx + 1}", text: line.strip }
        rescue ArgumentError
          next
        end
      end
      writers = lines.select { |m| m[:text].match?(WRITE_RE) }
      readers = lines.select { |m| m[:text].match?(READ_RE) } - writers
      {
        literal: lit, vars: names,
        readers: readers.map { |m| m[:at] }, writers: writers.map { |m| m[:at] },
        writerless: readers.any? && writers.empty?,
      }
    end
    rows.select { |r| r[:readers].any? || r[:writers].any? }
        .sort_by { |r| [r[:writerless] ? 0 : 1, r[:literal]] }
  end
end

if __FILE__ == $PROGRAM_NAME
  root = File.expand_path(ARGV[0] || Dir.pwd)
  rows = AttestationAudit.audit(root)
  puts JSON.pretty_generate({ root:, writerless: rows.count { |r| r[:writerless] }, rows: })
  exit(rows.any? { |r| r[:writerless] } ? 1 : 0)
end
