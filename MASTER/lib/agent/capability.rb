# frozen_string_literal: true

# bin/master capability - the constitution in a pocket.
#
# Governed delivery degrades monotonically as capability falls: every lower
# tier owes a subset of the next higher tier's obligations and a subset of
# its proof surface - never a different one. This command detects the host's
# tier, prints what that tier owes and what it may claim, and verifies the
# monotonicity of the declared tiers mechanically, so
# CAPABILITY_REDUCTION_IS_MONOTONIC is a property of the screen rather than
# a rule to remember.

require "yaml"
require_relative "fast_gate"

module Master
  module Agent
    module Capability
      extend Base

      class << self
        include Base

        def run(argv)
          action = argv.first.to_s
          action = "detect" if action.empty?
          case action
          when "detect" then detect
          when "tiers" then tiers_view
          else
            puts "usage: bin/master capability detect|tiers"
            exit(64)
          end
        end

        def tiers
          @tiers ||= load_yaml(data_path("capability_tiers.yml")).fetch("tiers", [])
        end

        def tiers_view
          emit(command: "capability tiers",
               tiers:,
               monotonicity: verify_monotonic,
               note: "each lower tier owes a subset of the higher tier's obligations; the monotonicity breach list is the proof that this holds")
          0
        end

        def detect
          current = host_tier
          row = tiers.find { |t| t["id"] == current }
          emit(command: "capability detect",
               host: {
                 ruby: RUBY_VERSION,
                 prism: prism_available?,
                 bundle: bundle_available?,
                 memory_mb: memory_mb,
                 termux: termux?,
               },
               tier: row,
               owes: row.fetch("laws"),
               may_claim: row.fetch("receipts"),
               monotonicity: verify_monotonic,
               note: "a lower tier says what it did not run; it never claims the higher tier's proof")
          0
        end

        # The monotonicity test: each tier's needs and laws are subsets of the
        # tier above it. A tier that adds an obligation as capability falls is
        # not a reduction; it is a different constitution, and the screen says
        # so.
        def verify_monotonic
          ladder = tiers
          breaches = []
          ladder.each_cons(2) do |higher, lower|
            missing_needs = Array(lower["needs"]).reject { |n| Array(higher["needs"]).include?(n) }
            missing_laws = Array(lower["laws"]).reject { |l| Array(higher["laws"]).include?(l) }
            breaches << { lower: lower["id"], higher: higher["id"], needs: missing_needs, laws: missing_laws } if missing_needs.any? || missing_laws.any?
          end
          { monotonic: breaches.empty?, breaches: }
        end

        private

        def host_tier
          return "full" if bundle_available? && chrome_available?
          return "fast" if bundle_available?
          return "bare" if prism_available?

          "pocket"
        end

        def prism_available?
          require "prism"
          true
        rescue LoadError
          false
        end

        def bundle_available?
          require "bundler"
          true
        rescue LoadError
          false
        end

        def chrome_available?
          %w[google-chrome chromium chrome].any? { |bin| system("command -v #{bin} >/dev/null 2>&1") }
        end

        def memory_mb
          mem = File.read("/proc/meminfo")[/MemTotal:\s+(\d+)/, 1]
          mem ? mem.to_i / 1024 : 0
        rescue StandardError
          0
        end

        def termux?
          !ENV["TERMUX_VERSION"].to_s.empty?
        end
      end
    end
  end
end
