# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "time"

module Master
  module Trace
    class ReplayReader
      FAILURE_PATTERN = /error|fail|violation|veto|timeout|rollback/i

      def initialize(root: Master::ROOT, recorder: nil)
        @root = root
        @recorder = recorder
        @event_log = Log::Event.new(root:)
      end

      def render(arg: "")
        mode, rest = parse_arg(arg)
        case mode
        when :turn
          render_turn
        when :failures
          render_events(limit: rest.to_i.positive? ? rest.to_i : 15, failures_only: true)
        when :date
          render_trace_date(rest)
        when :commit
          render_commit(rest)
        when :evidence
          render_evidence(limit: rest.to_i.positive? ? rest.to_i : 20)
        else
          render_events(limit: mode.is_a?(Integer) ? mode : 20)
        end
      end

      def render_session_receipt(session:)
        key = session.current_key
        messages = session.messages(key)
        transcript = transcript_fingerprint(key)
        activity = session_event_summary("activity")
        evidence = session_event_summary("evidence")
        sources_read = [transcript, activity, evidence].all? { |source| source["status"] == "read" }
        status = sources_read ? "OBSERVED" : "INCONCLUSIVE"

        roles = messages.group_by { |message| (message[:role] || message["role"]).to_s }
        execution = messages.count do |message|
          layer = message[:layer] || message["layer"]
          Master::CLI::ContextLayers.normalize(layer) == :execution
        end
        timestamps = messages.filter_map do |message|
          value = message[:ts] || message["ts"]
          Integer(value, exception: false)
        end.sort
        time_range = if timestamps.empty?
                       "not recorded"
                     else
                       "#{Time.at(timestamps.first).utc.iso8601}..#{Time.at(timestamps.last).utc.iso8601}"
                     end

        [
          "session receipt0: #{status} (read-only; message text and event payloads omitted)",
          "transcript0: #{transcript_line(transcript, messages.size)}",
          "messages0: total=#{messages.size} user=#{roles.fetch("user", []).size} assistant=#{roles.fetch("assistant", []).size} execution=#{execution} time=#{time_range}",
          "activity0: #{event_summary_line(activity)}",
          "evidence0: #{event_summary_line(evidence)}",
          "privacy0: raw transcript text, tool arguments and telemetry payloads are not included",
        ].join("\n")
      rescue StandardError => error
        "session receipt0: INCONCLUSIVE (read-only summary failed: #{error.class})"
      end

      private

      def transcript_fingerprint(key)
        local = key.to_s == Session::LOCAL.to_s
        filename = local ? "session.json" : "conversations.json"
        path = File.join(@root, ".master", filename)
        return { "status" => "missing", "path" => ".master/#{filename}" } unless File.exist?(path) || File.symlink?(path)

        bytes = read_private_snapshot(path)
        data = JSON.parse(bytes)
        messages = if local
                     data["messages"]
                   else
                     data.dig(key.to_s, "messages") if data.is_a?(Hash) && data[key.to_s].is_a?(Hash)
                   end
        raise JSON::ParserError, "stored transcript messages are not an array" unless messages.is_a?(Array)

        {
          "status" => "read",
          "path" => ".master/#{filename}",
          "bytes" => bytes.bytesize,
          "sha256" => Digest::SHA256.hexdigest(bytes),
          "persisted_messages" => messages.size,
        }
      rescue StandardError => error
        { "status" => "unavailable", "path" => ".master/#{filename}", "error" => error.class.to_s }
      end

      def read_private_snapshot(path)
        before = File.lstat(path)
        unless before.file? && !before.symlink? && before.nlink == 1
          raise ArgumentError, "transcript must be a singly linked regular file"
        end

        flags = File::RDONLY
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(path, flags) do |file|
          opened = file.stat
          unless opened.file? && opened.dev == before.dev && opened.ino == before.ino &&
                 (opened.mode & 0o077).zero?
            raise ArgumentError, "transcript identity or permissions changed"
          end

          content = file.read
          after = File.lstat(path)
          unless after.file? && !after.symlink? && after.dev == opened.dev && after.ino == opened.ino
            raise ArgumentError, "transcript changed while being read"
          end
          content
        end
      end

      def session_event_summary(stream)
        records = Log::Event.new(root: @root, stream:).recent!(500)
        session_id = Log.session
        scoped = records.select { |record| record["session"] == session_id }
        counts = scoped.each_with_object(Hash.new(0)) do |record, out|
          name = record["event"].to_s
          out[name] += 1 unless name.empty?
        end
        ordered = counts.sort_by { |name, count| [-count, name] }
        flagged = ordered.select { |name, _count| name.match?(/error|fail|violation|veto|timeout|rollback|discard|drop|reject/i) }
        {
          "status" => "read",
          "sampled" => records.size,
          "session_events" => scoped.size,
          "event_types" => ordered.first(8),
          "omitted_types" => [ordered.size - 8, 0].max,
          "failure_like" => flagged,
        }
      rescue StandardError => error
        { "status" => "unavailable", "error" => error.class.to_s, "sampled" => 0, "session_events" => 0 }
      end

      def transcript_line(transcript, memory_count)
        detail = ["status=#{transcript.fetch("status")}"]
        detail << "path=#{transcript["path"]}" if transcript["path"]
        detail << "bytes=#{transcript["bytes"]}" if transcript["bytes"]
        detail << "sha256=#{transcript["sha256"]}" if transcript["sha256"]
        detail << "persisted_messages=#{transcript["persisted_messages"]}" if transcript["persisted_messages"]
        detail << "memory_messages=#{memory_count}"
        detail << "error=#{transcript["error"]}" if transcript["error"]
        detail.join(" ")
      end

      def event_summary_line(summary)
        types = Array(summary["event_types"]).map { |name, count| "#{name}=#{count}" }
        failure = Array(summary["failure_like"]).map { |name, count| "#{name}=#{count}" }
        [
          "status=#{summary.fetch("status")}",
          "sampled=#{summary.fetch("sampled", 0)}",
          "session_events=#{summary.fetch("session_events", 0)}",
          "types=#{types.empty? ? "none" : types.join(",")}",
          ("omitted_types=#{summary["omitted_types"]}" if summary["omitted_types"].to_i.positive?),
          ("failure_like=#{failure.join(",")}" unless failure.empty?),
          ("error=#{summary["error"]}" if summary["error"]),
        ].compact.join(" ")
      end

      private

      def parse_arg(arg)
        tokens = arg.to_s.strip.split(/\s+/, 2)
        head = tokens.first.to_s.downcase
        tail = tokens[1].to_s
        case head
        when "", "activity" then [:activity, tail]
        when "turn" then [:turn, tail]
        when "failures" then [:failures, tail]
        when "commit" then [:commit, tail]
        when "evidence" then [:evidence, tail]
        when /\A\d+\z/ then [head.to_i, tail]
        when /\A\d{4}-\d{2}-\d{2}\z/ then [:date, head]
        else [:activity, arg.to_s]
        end
      end

      def render_events(limit:, failures_only: false)
        records = @event_log.recent(limit * 3)
        records = records.select { |rec| rec["event"].to_s.match?(FAILURE_PATTERN) } if failures_only
        records = records.last(limit)
        return "replay: no #{failures_only ? "failure " : ""}events" if records.empty?

        lines = ["replay activity (#{records.size})"]
        records.each { |rec| lines << format_record(rec) }
        lines.join("\n")
      end

      def render_turn
        turn = @recorder&.last_turn
        turn ||= load_last_turn_from_disk
        return @recorder.pretty_last if turn.nil? && @recorder
        return "replay: no turn trace recorded" unless turn

        lines = ["replay turn #{turn[:id]}", "  channel=#{turn[:channel]}  message=#{turn.fetch(:message, "")[0, 80]}"]
        Array(turn[:events]).each do |ev|
          ms = ev[:ts_ms] || ev["ts_ms"]
          name = ev[:event] || ev["event"]
          detail = (ev.is_a?(Hash) ? ev : {}).except(:ts_ms, :event, "ts_ms", "event").reject { |_, v| v.nil? }
          lines << "  +#{ms.to_s.rjust(5)}ms  #{name}  #{detail.empty? ? "" : detail.inspect}"
        end
        lines.join("\n")
      end

      def render_trace_date(date)
        path = File.join(@root, "data", "traces", "#{date}.jsonl")
        return "replay: no trace file for #{date}" unless File.file?(path)

        lines = ["replay traces #{date}"]
        File.foreach(path).each_with_index do |line, index|
          turn = JSON.parse(line, symbolize_names: true)
          lines << "turn #{index + 1}: #{turn[:id]} #{turn[:message].to_s[0, 60]}"
        end
        lines.join("\n")
      rescue JSON::ParserError => e
        "replay: corrupt trace file (#{e.message})"
      end

      def format_record(rec)
        ts = (Time.parse(rec["timestamp"]) rescue Time.now.utc).strftime("%H:%M:%S")
        event = rec["event"].to_s.ljust(28)
        pay = rec["payload"]
        summary = pay.is_a?(Hash) ? pay.first(4).map { |k, v| "#{k}=#{v.to_s.tr('"', "")[0, 24]}" }.join(" ") : pay.to_s
        "#{ts} #{event} #{summary[0, 100]}"
      end

      def render_commit(sha)
        sha = sha.to_s.strip
        return "replay: usage: /replay commit <sha>" if sha.empty?

        info = commit_info(sha)
        return info if info.is_a?(String)

        window = 300
        events = nearby_events(info[:time], window:)
        lines = [
          "replay commit #{info[:short]} #{info[:subject]}",
          "  author=#{info[:author]} at=#{info[:time].utc.iso8601}",
          "  events ±#{window}s (#{events.size})",
        ]
        events.each { |rec| lines << "  #{format_record(rec)}" }
        lines.join("\n")
      end

      def render_evidence(limit:)
        log = Log::Evidence.new(root: @root)
        records = log.recent(limit)
        return "replay: no evidence events" if records.empty?

        lines = ["replay evidence (#{records.size})"]
        records.each { |rec| lines << format_record(rec) }
        lines.join("\n")
      end

      def commit_info(sha)
        repo = File.expand_path("..", @root)
        out, _, status = Master::Io::Exec.capture3(
          "git", "-C", repo, "show", "-s", "--format=%H|%h|%an|%aI|%s", sha
        )
        return "replay: commit not found: #{sha}" unless status.success? && !out.strip.empty?

        full, short, author, at, subject = out.strip.split("|", 5)
        { full:, short:, author:, time: Time.parse(at), subject: subject.to_s }
      rescue StandardError => e
        "replay: commit lookup failed (#{e.message})"
      end

      def nearby_events(center, window:)
        start_at = center - window
        end_at = center + window
        @event_log.recent(500).select do |rec|
          ts = (Time.parse(rec["timestamp"]) rescue nil)
          ts && ts >= start_at && ts <= end_at
        end
      end

      def load_last_turn_from_disk
        dir = File.join(@root, "data", "traces")
        files = Dir.glob(File.join(dir, "*.jsonl")).sort
        return if files.empty?

        last_line = nil
        File.foreach(files.last) { |line| last_line = line }
        last_line ? JSON.parse(last_line, symbolize_names: true) : nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplayReader.load_last_turn_from_disk")
        nil
      end
    end
  end
end
