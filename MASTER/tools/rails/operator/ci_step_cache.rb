# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"

module Operator
  # Per-step reuse for RAILS bin/ci. A step whose inputs (git trees) and Ruby
  # are unchanged since a recorded pass under seven days old is reported as
  # reused instead of rerun. System tests were the slowest and flakiest part of
  # every deploy's CI and reran on commits that touched no view, asset or
  # script; rubocop and brakeman reran on commits that touched no Ruby
  # (operator, 2026-11-25: "do 3 and 4, keep CI on the mac").
  #
  # Uncommitted changes under any input make the step run: the key describes
  # HEAD, so a dirty tree cannot be described by it.
  module CiStepCache
    MAX_AGE = 7 * 24 * 3600

    module_function

    def directory = File.expand_path(ENV.fetch("PUB5_CI_RECEIPT_DIR", "~/.pub5/ci"), "steps")

    # The step's shell command: an echo when a pass can be reused, otherwise the
    # command followed by recording its pass.
    # spec: { app:, step:, inputs:, run: }
    def command(repo, spec)
      app, step, inputs, run = spec.values_at(:app, :step, :inputs, :run)
      return run if ENV["PUB5_CI_NO_CACHE"] == "1"

      key = key(repo:, inputs:)
      return run unless key

      prior = reusable(app:, step:, key:)
      return "echo 'ci: #{step} inputs unchanged since #{prior['sha'][0, 9]}; reusing its pass'" if prior

      "#{run} && #{RbConfig.ruby} #{__FILE__} record #{app} #{step} #{key} #{head(repo)}"
    end

    # nil when any input is dirty or unreadable, so the step runs.
    def key(repo:, inputs:)
      paths = inputs.select { |path| tracked?(repo, path) }
      return if paths.empty? || dirty?(repo, paths)

      trees = paths.map { |path| "#{path}=#{git(repo, 'rev-parse', "HEAD:#{path}")}" }
      Digest::SHA256.hexdigest([*trees, "ruby=#{RUBY_VERSION}"].join("\n"))
    rescue RuntimeError => e
      warn "ci: step inputs unreadable (#{e.message}); running uncached"
      nil
    end

    def reusable(app:, step:, key:, now: Time.now)
      file = path(app, step)
      return unless File.file?(file)

      record = JSON.parse(File.read(file))
      record if record["key"] == key && (now - Time.iso8601(record.fetch("passed_at"))).between?(0, MAX_AGE)
    rescue JSON::ParserError, KeyError, ArgumentError => e
      warn "ci: ignoring unreadable step receipt #{file}: #{e.class}"
      nil
    end

    def record!(app:, step:, key:, sha:)
      FileUtils.mkdir_p(directory, mode: 0o700)
      record = { "app" => app, "step" => step, "key" => key, "sha" => sha, "passed_at" => Time.now.utc.iso8601 }
      File.write(path(app, step), "#{JSON.generate(record)}\n")
    end

    def path(app, step) = File.join(directory, "#{app}-#{step}.json")

    def head(repo) = git(repo, "rev-parse", "HEAD")

    def tracked?(repo, path)
      _out, status = Open3.capture2e("git", "-C", repo, "cat-file", "-e", "HEAD:#{path}")
      status.success?
    end

    def dirty?(repo, paths)
      !git(repo, "status", "--porcelain", "--", *paths).empty?
    end

    def git(repo, *args)
      out, status = Open3.capture2("git", "-C", repo, *args, err: File::NULL)
      raise "git #{args.first} failed" unless status.success?

      out.strip
    end
  end
end

if $PROGRAM_NAME == __FILE__ && ARGV.first == "record"
  _, app, step, key, sha = ARGV
  Operator::CiStepCache.record!(app:, step:, key:, sha:)
end
