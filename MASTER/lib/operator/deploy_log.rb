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
      @path = path ? validated_existing_path(path) : create_path(clock.call)
      append([
        "pub5 deployment transcript",
        "app: #{@app}",
        "sha: #{@sha}",
        "started_utc: #{clock.call.iso8601}",
        "log: #{@path}",
        "",
      ].join("\n"))
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
      publication =
        if outcome.success?
          "paste: #{outcome.url} (#{outcome.expires_in}, redacted)"
        else
          reason = outcome.error || outcome.respond_to?(:skipped) && outcome.skipped || "not published"
          "paste: unavailable (#{reason})"
        end
      append("\n#{publication}\n")
      write_status(exit_code)
      outcome
    rescue StandardError => error
      append("\npaste: publication error (#{error.class})\n") rescue nil
      write_status(exit_code) rescue nil
      raise
    end

    def self.read_status(path)
      status_path = "#{File.expand_path(path)}.status"
      return nil unless File.file?(status_path) && !File.symlink?(status_path)

      content = File.read(status_path)
      match = content.match(/\Aexit=(\d+)\n?\z/)
      match && Integer(match[1], 10)
    rescue SystemCallError, ArgumentError
      nil
    end

    private

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
