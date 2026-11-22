# frozen_string_literal: true

require "json"
require_relative "../boot/paths"
require_relative "../trace/dmesg"

module Operator
  # `bin/operator fix tail`: follows one representation at a time.
  # Default shows the human run log; --transcript selects detailed NDJSON
  # evidence. The human tail never merges two renderings of the same work.
  module FixTail
    POLL_SECONDS = 0.5
    DEFAULT_LINES = 20

    module_function

    # argv: --tail[=N] lines of history first, --transcript for the records
    # only, --once to print and stop instead of following.
    def run(argv, roots:, io: $stdout, sleeper: ->(seconds) { sleep(seconds) }, rounds: nil)
      lines = argv.filter_map { |arg| arg[/\A--(?:tail|n)=(\d+)\z/, 1] }.first
      limit = (lines || DEFAULT_LINES).to_i
      transcript_only = argv.include?("--transcript")
      once = argv.include?("--once")
      found = sources(roots, transcript_only)
      return missing(io) if found.empty?

      offsets = {}
      print_history(found, limit, offsets, io)
      return 0 if once

      count = 0
      loop do
        break if rounds && (count += 1) > rounds

        sleeper.call(POLL_SECONDS)
        print_new(sources(roots, transcript_only), offsets, io)
      end
      0
    end

    def missing(io)
      Master::Trace::Dmesg.status("fix0", "no /fix log or transcript found", io:)
      1
    end

    def sources(roots, transcript_only)
      directories = state_roots(roots)
      if transcript_only
        newest = directories.flat_map { |root| Dir.glob(File.join(root, "fix_transcripts", "*")) }
                            .select { |path| File.directory?(path) }.max_by { |path| File.mtime(path) }
        return newest ? Dir.glob(File.join(newest, "*.ndjson")).sort : []
      end

      log = directories.flat_map { |root| Dir.glob(File.join(root, "fix-*.log")) }
                        .max_by { |path| File.mtime(path) }
      log ? [log] : []
    end

    # New state is preferred, while legacy locations remain readable until the
    # first writable /fix invocation completes its copy-verified cutover.
    def state_roots(roots)
      roots.flat_map do |root|
        workspace = File.basename(File.expand_path(root)) == "MASTER" ? File.dirname(File.expand_path(root)) : File.expand_path(root)
        [
          MasterPaths.fix_state(root: root),
          File.join(workspace, ".master"),
          File.join(workspace, "MASTER", ".master"),
          File.join(root, ".master"),
        ]
      end.map { |path| File.expand_path(path) }.uniq
    end

    def print_history(paths, limit, offsets, io)
      rows = paths.flat_map do |path|
        raw = File.binread(path)
        offsets[path] = raw.bytesize
        raw.force_encoding("UTF-8").scrub.lines.each_with_index.map do |line, index|
          [row_time(path, line), path, index, line]
        end
      end
      rows.sort_by! { |at, path, index, _line| [at, path, index] }
      visible = rows.filter_map do |_at, path, _index, line|
        rendered = render(path, line)
        rendered unless rendered.nil? || rendered.empty?
      end
      visible.last(limit).each { |line| io.puts(line) }
      io.flush
    end

    def print_new(paths, offsets, io)
      rows = paths.flat_map do |path|
        size = File.size(path)
        from = offsets.fetch(path, 0)
        from = 0 if size < from
        next [] if size == from

        chunk = File.open(path, "rb") { |file| file.seek(from) && file.read }.to_s
        newline = chunk.rindex("\n")
        next [] unless newline

        complete = chunk.byteslice(0, newline + 1)
        offsets[path] = from + complete.bytesize
        complete.force_encoding("UTF-8").scrub.lines.each_with_index.map do |line, index|
          [row_time(path, line), path, index, line]
        end
      end
      rows.sort_by! { |at, path, index, _line| [at, path, index] }
      rows.each do |_at, path, _index, line|
        rendered = render(path, line)
        io.puts(rendered) unless rendered.nil? || rendered.empty?
      end
      io.flush unless rows.empty?
    end

    def row_time(path, line)
      return "" unless path.end_with?(".ndjson")

      JSON.parse(line)["at"].to_s
    rescue JSON::ParserError
      ""
    end

    def render(path, line)
      unless path.end_with?(".ndjson")
        text = line.chomp
        # Script-facing key/value beats stay in the raw log, not the human tail.
        return if text.match?(/\Afix0 phase=\S+ fixed=\d+ failed=\d+ rejected=\d+/)

        return text
      end

      row = JSON.parse(line)
      detail = [row["law"], row["file"] && File.basename(row["file"]), row["outcome"] || row["reason"], row["pick"] && row["pick"].to_s[0, 160], row["status"]].compact.join(" ")
      "#{File.basename(path, ".ndjson")}: #{row["at"]} #{row["kind"]} #{detail}".strip
    rescue JSON::ParserError
      line.chomp
    end
  end
end
