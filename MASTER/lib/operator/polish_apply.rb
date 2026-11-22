# frozen_string_literal: true

require "yaml"
require "digest"
require "fileutils"
require "time"

module Operator
  module PolishLens
    # Bounded implementation half. Discovery stays read-only by default; this
    # adds an operator-gated --apply for the strictly mechanical, reversible
    # subset, suitable as an argv-allowlisted /fix implementer. It writes
    # nothing without --apply, refuses sacred paths and rendered values,
    # consults antigen memory, and emits a receipt per edit. Taste, rendered
    # and live-host decisions are never applied; they remain operator-owned.
    APPLY_KINDS = %w[keep_hygiene exec_bit shebang_portability].freeze

    module_function

    def collect(root)
      CHECKS.flat_map { |c| send(c, root) }.sort_by { |f| [f.path, f.line.to_i, f.id] }
    end

    def sacred_paths(root)
      soul = File.join(root, "MASTER/data/soul.yml")
      return [] unless File.exist?(soul)
      d = YAML.safe_load(File.read(soul), aliases: true) || {}
      Array(d.dig("absolute", "sacred_paths")).map { |p| p.to_s.sub(%r{^\./}, "") }
    rescue StandardError
      :unreadable
    end

    def sacred?(root, path)
      sp = sacred_paths(root)
      return true if sp == :unreadable # fail closed: never edit what we cannot verify
      sp.any? { |s| path == s || path.start_with?(s.chomp("/") + "/") }
    end

    def memory_dir(root) = File.join(root, ".master", "polish")

    def antigens(root)
      f = File.join(memory_dir(root), "antigens.yml")
      return [] unless File.exist?(f)
      YAML.safe_load(File.read(f), permitted_classes: [Date, Time], aliases: true) || []
    rescue StandardError
      []
    end

    def antigen?(root, f)
      antigens(root).any? { |a| a["id"] == f.id && (a["path"].nil? || a["path"] == f.path) }
    end

    def remember_antigen(root, f, reason)
      FileUtils.mkdir_p(memory_dir(root))
      list = antigens(root)
      list << { "id" => f.id, "path" => f.path, "kind" => f.kind, "reason" => reason,
                "date" => Time.now.utc.strftime("%Y-%m-%d") }
      File.write(File.join(memory_dir(root), "antigens.yml"), YAML.dump(list))
    end

    def apply_one(root, f)
      path = File.join(root, f.path)
      return [:missing, nil] unless File.exist?(path)
      case f.id
      when "keep_hygiene"
        before = Digest::SHA256.file(path).hexdigest
        File.delete(path)
        [:applied, before]
      when "exec_bit"
        before = format("%o", File.stat(path).mode & 0o7777)
        FileUtils.chmod(0o755, path)
        [:applied, before]
      when "shebang_portability"
        src = File.read(path)
        before = Digest::SHA256.hexdigest(src)
        new = src.sub(%r{^#!/usr/(local/)?bin/ruby\b}, "#!/usr/bin/env ruby")
        return [:unchanged, before] if new == src
        File.write(path, new)
        [:applied, before]
      else
        [:refused_kind, nil]
      end
    end

    def receipt(root, f, status, before)
      FileUtils.mkdir_p(File.join(memory_dir(root), "receipts"))
      fp = File.join(root, f.path)
      after = File.exist?(fp) ? Digest::SHA256.file(fp).hexdigest : nil
      r = { "id" => f.id, "path" => f.path, "kind" => f.kind, "law" => f.law,
            "status" => status.to_s, "before" => before, "after" => after,
            "proof" => f.proof, "utc" => Time.now.utc.iso8601 }
      name = "#{Time.now.utc.strftime('%Y%m%dT%H%M%S%L')}-#{f.id}.yml"
      File.write(File.join(memory_dir(root), "receipts", name), YAML.dump(r))
      r
    end

    def apply(root: ROOT, only: nil, dry_run: true, reject: nil)
      findings = collect(root)
      findings = findings.select { |f| only.include?(f.id) } if only
      if reject
        n = 0
        findings.each { |f| (remember_antigen(root, f, "operator rejected via --reject"); n += 1) if reject.include?(f.id) }
        puts "polish: recorded #{n} antigens"
        return findings
      end
      receipts = []
      findings.each do |f|
        status =
          if !APPLY_KINDS.include?(f.id) then :refused_kind
          elsif sacred?(root, f.path) then :refused_sacred
          elsif antigen?(root, f) then :refused_antigen
          end
        if status
          receipts << receipt(root, f, status, nil) unless dry_run
          puts "#{status}: #{f.id} #{f.path}" unless dry_run
          next
        end
        if dry_run
          puts "would apply: #{f.id} #{f.path} (#{f.edit})"
          next
        end
        st, before = apply_one(root, f)
        receipts << receipt(root, f, st, before)
        puts "#{st}: #{f.id} #{f.path}"
      end
      puts "polish: apply complete; #{receipts.size} receipts" unless dry_run
      receipts
    end
  end
end
