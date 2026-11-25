# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"

module Operator
  # Lets a deploy reuse an app's bin/ci pass when nothing that CI reads has
  # changed. Every new commit used to rerun every app's full suite (~25 min on
  # the workstation), even a commit that touched only OPENBSD or MASTER docs:
  # on 2026-11-25 that cost most of a day's deploy attempts.
  #
  # The key is the git tree ids CI reads (the app, RAILS/__shared, the
  # top-level RAILS files and MASTER/tools, where its lints live) plus the Ruby
  # it runs under. Same trees, same Ruby: the same suite would run on the same
  # bytes, so a recorded pass stands. Any change to any of them forces a run.
  module CiReceipt
    MAX_AGE = 7 * 24 * 3600
    TREES = ["RAILS/__shared", "MASTER/tools"].freeze

    module_function

    def directory = File.expand_path(ENV.fetch("PUB5_CI_RECEIPT_DIR", "~/.pub5/ci"))

    def key(root:, app:, ruby_version:)
      parts = ["RAILS/#{app}", *TREES].map { |path| "#{path}=#{tree_id(root, path)}" }
      parts << "RAILS/*=#{rails_top_level(root)}" << "ruby=#{ruby_version}"
      Digest::SHA256.hexdigest(parts.join("\n"))
    end

    # The recorded pass for this exact key, or nil when there is none, it is
    # stale, or the record cannot be read.
    def reusable(app:, key:, now: Time.now)
      return unless File.file?(path(app))

      record = JSON.parse(File.read(path(app)))
      return unless record["key"] == key

      age = now - Time.iso8601(record.fetch("passed_at"))
      record if age.between?(0, MAX_AGE)
    rescue JSON::ParserError, KeyError, ArgumentError => e
      warn "ci0: ignoring unreadable CI receipt #{path(app)}: #{e.class}"
      nil
    end

    def record!(app:, key:, sha:, now: Time.now)
      FileUtils.mkdir_p(directory, mode: 0o700)
      record = { "app" => app, "key" => key, "sha" => sha, "passed_at" => now.utc.iso8601 }
      File.write(path(app), "#{JSON.generate(record)}\n")
    end

    def path(app) = File.join(directory, "#{app}.json")

    def tree_id(root, path)
      out, status = Open3.capture2("git", "-C", root, "rev-parse", "HEAD:#{path}", err: File::NULL)
      raise "cannot read tree #{path}" unless status.success?

      out.strip
    end

    # Blobs directly under RAILS/ (apps.yml, shared Gemfile pieces and the
    # like): subtrees are other apps, which do not change this app's suite.
    def rails_top_level(root)
      out, status = Open3.capture2("git", "-C", root, "ls-tree", "HEAD", "RAILS/", err: File::NULL)
      raise "cannot list RAILS/" unless status.success?

      blobs = out.lines.select { |line| line.split[1] == "blob" }
      Digest::SHA256.hexdigest(blobs.join)
    end
  end
end
