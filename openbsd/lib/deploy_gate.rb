# frozen_string_literal: true
require "digest"
require_relative "rehearsal"

module OpenBSD
  class DeployGate
    def initialize(root:)
      @root = File.realpath(root)
      @rehearsal = Rehearsal.new(root: @root)
    end

    def plan
      live, missing = @rehearsal.live_status
      failed = @rehearsal.verify_sources.reject { |row| row.status == "PASS" }
      { "source_status" => failed.empty? ? "PASS" : "FAIL", "live_status" => live, "missing_observations" => missing, "ship_status" => "BLOCKED" }
    end

    def verify_artifact(path, expected_sha256:)
      candidate = File.realpath(path)
      prefix = "#{@root}#{File::SEPARATOR}"
      raise ArgumentError, "artifact must be outside the checkout" if candidate == @root || candidate.start_with?(prefix)
      actual = Digest::SHA256.file(candidate).hexdigest
      raise ArgumentError, "artifact SHA-256 mismatch" unless actual == expected_sha256.to_s.downcase
      { "path" => candidate, "sha256" => actual, "status" => "PASS" }
    end
  end
end
