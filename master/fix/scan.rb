# frozen_string_literal: true

require "digest"
require "json"

module Fix
  # The tree's content key (pub4 fe241a94cf's RatchetCache key): the
  # committed tree id, the working diff and the untracked files' bytes, so an
  # uncommitted edit counts like a commit.
  module TreeDigest
    # Larger files are data (renders, fixtures, vendored code), not source a Law reads.
    MAX_BYTES = 1_000_000

    module_function

    def key(world, scope)
      head = world.git("rev-parse", "HEAD:#{scope == '.' ? '' : scope}").out.strip
      diff = world.git("diff", "HEAD", "--binary", "--", scope).out
      untracked = files(world, "--others", "--exclude-standard", scope).sort.map { |f| "#{f}\0#{digest(world, f)}" }
      Digest::SHA256.hexdigest([scope, head, Digest::SHA256.hexdigest(diff), *untracked].join("\0"))
    end

    # path => content id: the index blob for a clean file, the bytes' digest
    # for a changed or untracked one.
    def ids(world, scope)
      root = world.manifest.root
      dirty = files(world, "--modified", "--others", "--exclude-standard", scope).to_h { |f| [f, true] }
      index = world.git("ls-files", "-s", "-z", "--", scope).out.split("\0").to_h do |row|
        meta, path = row.split("\t", 2)
        [path, meta.split[1]]
      end
      (index.keys | dirty.keys).each_with_object({}) do |path, out|
        full = File.join(root, path)
        next unless File.file?(full) && File.size(full) <= MAX_BYTES

        out[path] = dirty[path] ? digest(world, path) : index[path]
      end
    end

    def files(world, *flags, scope) = world.git("ls-files", "-z", *flags, "--", scope).out.split("\0")

    def digest(world, path) = Digest::SHA256.hexdigest(world.read(path))
  end

  # The scan /fix repairs from: every Law that scans (enforced and
  # advisory; a broken or retired one does not), over the scope's tracked and
  # untracked files, incremental. Findings are cached per file by content id
  # and per Law set, and the whole result by the tree key, so an unchanged
  # tree answers at once and a changed one rescans only the files that
  # changed (PLAN.md section 6.6). Ratchets are Laws of the same engine: the
  # closing scan may not raise any Law's count over the opening one.
  class Scan
    CACHE = "tmp/fix/scan.json"
    Result = Data.define(:findings, :files, :scanned, :seconds, :cached_tree)

    attr_reader :laws

    def initialize(world:, laws:, scope:)
      @world = world
      @laws = laws
      @scope = scope
    end

    def self.scanning(laws, focus: nil)
      chosen = laws.reject { |law| law.broken || law.lifecycle == "retired" || !law.deterministic? }
      return chosen unless focus

      picked = chosen.select { |law| law.id.to_s == focus.to_s }
      raise ArgumentError, "--focus #{focus}: no scanning Law by that id" if picked.empty?

      picked
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cache = load
      tree = TreeDigest.key(@world, @scope)
      laws_key = laws_digest
      if cache["tree"] == tree && cache["laws"] == laws_key
        findings = cache.fetch("files").flat_map { |path, row| revive(path, row) }
        return result(findings, cache["files"].size, 0, started, true)
      end

      stored = cache["laws"] == laws_key ? cache.fetch("files", {}) : {}
      ids = TreeDigest.ids(@world, @scope)
      scanned = 0
      files = ids.to_h do |path, id|
        row = stored[path]
        next [path, row] if row && row["id"] == id

        scanned += 1
        [path, { "id" => id, "findings" => scan_file(path).map { |f| [f.law.to_s, f.line, f.text, f.message] } }]
      end
      save("tree" => tree, "laws" => laws_key, "files" => files)
      result(files.flat_map { |path, row| revive(path, row) }, files.size, scanned, started, false)
    end

    def scan_file(path)
      text = @world.read(path).force_encoding("UTF-8").scrub
      return [] if text.include?("\0")

      @laws.flat_map { |law| law.scan(text, path) }
    end

    private

    def result(findings, files, scanned, started, cached)
      Result.new(findings:, files:, scanned:, cached_tree: cached,
                 seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2))
    end

    def revive(path, row)
      row.fetch("findings").map { |law, line, text, message| Law::Finding.new(law.to_sym, path, line, text, message) }
    end

    # The Law set's key: the ids scanning, and the bytes of the files that define them.
    def laws_digest
      files = Law.files(File.join(Core::ROOT, "laws")) + [File.join(Core::ROOT, "registry", "laws.yml")]
      Digest::SHA256.hexdigest([@laws.map(&:id).sort.join(","), *files.map { |f| Digest::SHA256.file(f).hexdigest }].join("\0"))
    end

    def load
      JSON.parse(@world.read(CACHE))
    rescue Core::Refusal, Errno::ENOENT, JSON::ParserError
      {}
    end

    def save(data) = @world.write(CACHE, JSON.generate(data))
  end
end
