# frozen_string_literal: true

require "json"

module Deploy
  # What `bin/vps-deploy` wrote after its last run, and whether a running
  # process is the build that run deployed.
  #
  # master reports the commit it booted as /health `deploy.git_sha`, and the
  # deploy records the commit it pulled in `last_deploy_master.json`. Each is
  # correct about itself. Both can be correct while disagreeing: a checkout
  # pulled after the deploy, then a reboot or a hand restart, boots code no
  # deploy ever ran, and every other check still passes. The comparison is the
  # only place that state becomes a fact.
  module DeployStamp
    DIR = "/var/db/pub5"

    module_function

    # The stamp's sha, or nil for an absent or unreadable stamp.
    def sha(app, dir: DIR)
      path = File.join(dir, "last_deploy_#{app}.json")
      return nil unless File.readable?(path)

      record = JSON.parse(File.read(path))
      return nil unless record.is_a?(Hash) && record["app"].to_s == app.to_s

      value = record["sha"].to_s
      value.match?(/\A[0-9a-f]{7,40}\z/i) ? value : nil
    rescue JSON::ParserError, TypeError, IOError, SystemCallError
      nil
    end

    # nil when the booted build is the stamped one, a failure line when not.
    # Short SHAs differ in length between `git rev-parse --short` runs as the
    # object count grows, so one naming a prefix of the other is the same commit.
    def booted_mismatch(app:, booted:, stamped:)
      booted = booted.to_s
      return "#{app} health: no deploy.git_sha - the booted build is unknown" if booted.empty?
      return nil if stamped.nil?

      stamped = stamped.to_s
      valid_sha = ->(value) { value.match?(/\A[0-9a-f]{7,40}\z/i) }
      unless valid_sha.call(booted) && valid_sha.call(stamped)
        return "#{app} health: invalid deploy identity (booted=#{booted.inspect}, stamped=#{stamped.inspect})"
      end
      return nil if booted.start_with?(stamped) || stamped.start_with?(booted)

      "#{app} health: booted #{booted} but last deploy stamped #{stamped} - " \
        "this process runs code no deploy ran; `bin/vps-deploy #{app}` makes them one"
    end
  end
end
