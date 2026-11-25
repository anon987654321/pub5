# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "time"
require_relative "../ground/redactor"
require_relative "../ground/paste_publisher"

module Operator
  # A deploy transcript belongs to the workstation that initiated the release.
  # The VPS keeps only structured recovery receipts; tmux scrollback is the
  # short-lived transport buffer from which this file is collected.
  class DeployLog
    DEFAULT_DIRECTORY = File.expand_path("~/.pub5/deployments")
    APP_ID = /\A[a-z][a-z0-9_-]{0,31}\z/
    SHA = /\A(?:[0-9a-f]{7,40}|unknown)\z/i
    STATUS = %w[success failure blocked inconclusive cancelled].freeze
    # The collector writes the public canary verdict under this heading and
    # MASTER's /deploy accepts a release only when it reads "(PASS)" after it.
    PUBLIC_CANARY = "post-deploy public canary"

    attr_reader :path, :app, :sha

    def initialize(app:, sha:, directory: ENV.fetch("PUB5_DEPLOY_LOG_DIR", DEFAULT_DIRECTORY),
                   path: nil, publisher: nil, clock: -> { Time.now.utc })
      raise ArgumentError, "invalid deploy app" unless APP_ID.match?(app.to_s)
      raise ArgumentError, "invalid deploy SHA" unless SHA.match?(sha.to_s)

      @app = app
      @sha = sha
      @directory = File.expand_path(directory)
      @publisher = publisher || Master::Ground::PastePublisher.new(root: File.expand_path("../../..", __dir__))
      @previous_snapshot = []
      ensure_directory!
      resumed = !path.nil?
      @path = resumed ? validated_existing_path(path) : create_path(clock.call)
      unless resumed
        append([
          "pub5 deployment transcript",
          "app: #{@app}",
          "sha: #{@sha}",
          "started_utc: #{clock.call.iso8601}",
          "log: #{@path}",
          "",
        ].join("\n"))
      end
    end

    def append(text)
      return if text.nil? || text.empty?

      verify_log!
      File.open(@path, File::WRONLY | File::APPEND) do |file|
        file.write(text)
        file.flush
        file.fsync
      end
      text
    end

    # tmux capture-pane returns its complete bounded history on each poll.
    # Append only the new suffix; an overlap fallback handles history scrolling.
    def append_snapshot(snapshot)
      current = snapshot.to_s.lines.map(&:chomp)
      current.pop while current.last == ""
      delta =
        if @previous_snapshot.empty?
          current
        elsif current.first(@previous_snapshot.length) == @previous_snapshot
          current.drop(@previous_snapshot.length)
        else
          overlap = [@previous_snapshot.length, current.length].min.downto(1).find do |size|
            @previous_snapshot.last(size) == current.first(size)
          end
          overlap ? current.drop(overlap) : current
        end
      @previous_snapshot = current
      return "" if delta.empty?

      chunk = "#{delta.join("\n")}\n"
      append(chunk)
      chunk
    end

    def status_path
      "#{@path}.status"
    end

    def finish(status:, exit_code:)
      raise ArgumentError, "invalid deploy status" unless STATUS.include?(status.to_s)

      verify_log!
      content = File.binread(@path)
      outcome = @publisher.publish(operation: "deploy #{@app}", status:, output: content)
      append("\n#{publication_line(outcome)}\n")
      write_status(exit_code)
      outcome
    rescue StandardError => error
      append("\npaste: publication error (#{error.class})\n") rescue nil
      write_status(exit_code) rescue nil
      raise
    end

    def self.read_status(path)
      status_path = "#{File.expand_path(path)}.status"
      return unless File.file?(status_path) && !File.symlink?(status_path)

      content = File.read(status_path)
      match = content.match(/\Aexit=(\d+)\n?\z/)
      match && Integer(match[1], 10)
    rescue SystemCallError, ArgumentError
      nil
    end

    # A failed run's cause sits inside the stage that failed, not on the last
    # line of the pane. These read the transcript text, from the file or from
    # the copy the operator streamed, and name the stage, its likely causes
    # and the local file that holds the rest.
    FAILED_STAGE = /\Avps-deploy: (\S+) FAILED at stage "([^"]+)" \(exit (\d+)\)/
    STAGE_LINE = /\A\S+Z host=\S+ pid=\d+ app=(\S+) stage=(\S+) (.*)\z/
    CAUSE = Regexp.union(
      /\bFAIL(?:ED)?\b|\b(?:failed|refused|denied|unable|could not)\b|BLOCKED|PROTECTED/,
      /not found|\w+Error\b|: nil\z|\A[\w.\/-]+:\d+: /
    )
    CAUSE_LIMIT = 4

    def self.failure_digest(text)
      lines = text.to_s.lines.map { |line| line.chomp.gsub(/<[^>]*>/, "").rstrip }
      failed = failed_stage(lines)
      return unless failed

      failed.merge(causes: failure_causes(lines, failed), transcript: transcript_path(lines))
    end

    def self.failed_stage(lines)
      index = lines.index { |line| line.match?(FAILED_STAGE) }
      if index
        app, stage, code = lines[index].match(FAILED_STAGE).captures
        return { app:, stage:, exit: Integer(code, 10), stop: index }
      end

      index = lines.index { |line| line[STAGE_LINE, 3].to_s.match?(/\Afinished exit=[1-9]/) }
      return unless index

      app, stage, rest = lines[index].match(STAGE_LINE).captures
      { app:, stage:, exit: Integer(rest[/\d+\z/], 10), stop: index }
    end

    # Lines between the failing stage's enter and its failure that read as a
    # cause; repeats collapse to one line with a count, newest causes win.
    # With no such line, the stage's last own line is the best witness.
    def self.failure_causes(lines, failed)
      window = stage_window(lines, failed)
      counts = cause_lines(window).tally
      return last_own_line(window) if counts.empty?

      counts.keys.last(CAUSE_LIMIT).map { |line| counts[line] > 1 ? "#{line} (x#{counts[line]})" : line }
    end

    def self.stage_window(lines, failed)
      stop = failed[:stop]
      enter = "stage=#{failed[:stage]} enter"
      start = lines[0...stop].rindex { |line| line.end_with?(enter) } || [stop - 40, 0].max
      lines[start...stop]
    end

    def self.last_own_line(window)
      window.reject { |line| line.strip.empty? || line.match?(STAGE_LINE) || line.start_with?("stamp0:") }
            .last(1).map { |line| line.strip[0, 160] }
    end

    def self.cause_lines(window)
      window.each_with_index.filter_map do |line, index|
        next if line.match?(STAGE_LINE)

        continued = line.match?(/\A\s+- /) && index.positive? && window[index - 1].match?(CAUSE)
        line.strip[0, 160] if continued || line.match?(CAUSE)
      end
    end

    def self.transcript_path(lines)
      lines.filter_map { |line| line[%r{\A(?:log|vps-deploy: capturing to):? (/\S+\.log)\z}, 1] }.last
    end

    # Ticker lines for a running deploy: each stage entry and each app the
    # fleet run moves to, as one short label per transcript line.
    def self.stage_label(line)
      app = line[/\Avps-deploy: all -> (\S+)\z/, 1]
      return app if app

      match = line.match(STAGE_LINE)
      return unless match && match[3] == "enter"

      stage = match[2].sub(/\Aall:/, "")
      match[1] == "all" || match[1] == stage ? stage : "#{match[1]} #{stage}"
    end

    private

    # Publishing is opt-in (MASTER_LOG_PUBLISH=1); a disabled publisher keeps
    # the transcript on this workstation and the line names where it is.
    def publication_line(outcome)
      return "paste: #{outcome.url} (#{outcome.expires_in}, redacted)" if outcome.success?
      return "paste: unavailable (#{outcome.error || "not published"})" unless outcome.error == :disabled

      "paste: not published; transcript kept at #{@path} (MASTER_LOG_PUBLISH=1 publishes)"
    end

    def ensure_directory!
      FileUtils.mkdir_p(@directory, mode: 0o700)
      raise "#{@directory} is a symlink" if File.symlink?(@directory)

      stat = File.lstat(@directory)
      raise "#{@directory} is not an owned directory" unless stat.directory? && stat.uid == Process.uid
      File.chmod(0o700, @directory)
    end

    def create_path(clock)
      stamp = clock.strftime("%Y%m%dT%H%M%SZ")
      name = "deploy-#{stamp}-#{@app}-#{@sha[0, 12]}-#{Process.pid}-#{SecureRandom.hex(3)}.log"
      path = File.join(@directory, name)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.fsync }
      path
    end

    def validated_existing_path(path)
      expanded = File.expand_path(path)
      raise ArgumentError, "deploy log must be directly inside #{@directory}" unless File.dirname(expanded) == @directory
      raise "#{expanded} is a symlink" if File.symlink?(expanded)

      stat = File.lstat(expanded)
      raise "#{expanded} is not an owned regular file" unless stat.file? && stat.uid == Process.uid
      raise "#{expanded} has unsafe permissions" unless (stat.mode & 0o077).zero?
      expanded
    end

    def verify_log!
      raise "#{@path} is a symlink" if File.symlink?(@path)
      stat = File.lstat(@path)
      raise "#{@path} is not an owned regular file" unless stat.file? && stat.uid == Process.uid
      raise "#{@path} has unsafe permissions" unless (stat.mode & 0o077).zero?
    end

    def write_status(exit_code)
      value = Integer(exit_code)
      raise ArgumentError, "invalid deployment exit code" unless (0..255).cover?(value)

      temporary = "#{status_path}.#{Process.pid}.#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write("exit=#{value}\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, status_path)
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end
  end
end
