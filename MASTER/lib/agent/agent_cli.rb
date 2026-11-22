# frozen_string_literal: true

# The zero-dependency agent tier: one stdlib-only surface at bin/master.
#
# This file loads before the full runtime boot. Nothing here may require
# bundler, the gem set, or lib/master: the whole point of the tier is that an
# agent on a dying host, a 1 GB box or a foreign tree gets real findings and
# real answers in seconds, deferring Chrome, libvips and the bundle until a
# rendered proof is actually requested.
#
# Every command answers in JSON by default (--json is implied), keeps one
# canonical source of truth (it never re-implements a law, a ledger or a
# policy), and marks what it did not execute as NOT_RUN rather than PASS.

require "json"
require "yaml"
require "optparse"

module Master
  module Agent
    module Base
      # MASTER/ is two levels up from lib/agent/.
      def master_root
        File.expand_path("../..", __dir__)
      end

      def repo_root
        File.expand_path("..", master_root)
      end

      def data_path(name)
        File.join(master_root, "data", name)
      end

      def load_yaml(path)
        YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
      rescue StandardError => e
        abort "agent: #{File.basename(path)} does not parse: #{e.class}: #{e.message}"
      end

      def laws_yml
        @laws_yml ||= load_yaml(data_path("laws.yml"))
      end

      def catalogue
        laws_yml.fetch("law_catalogue")
      end

      def catalogue_entries
        catalogue.fetch("entries")
      end

      # The temperament refuses in one dry, exact paragraph: why, and what
      # evidence would change the answer. A refusal that explains itself can
      # be argued with; a bare exit code cannot.
      def refuse(command, why, evidence_needed)
        warn <<~REFUSAL
          BLOCKED: #{command} did not run.
          Why: #{why}
          What would change this: #{evidence_needed}
          Nothing was measured; any downstream status is NOT_RUN, not PASS.
        REFUSAL
        exit 78
      end

      def emit(payload)
        puts JSON.pretty_generate(payload)
      end

      def not_run(step, why)
        { step:, status: "NOT_RUN", why: }
      end
    end

    module CLI
      extend Base

      COMMANDS = {
        "scan" => "bare_scan",
        "laws" => "law_index",
        "status" => "status_view",
        "owns" => "owns",
        "orient" => "orient",
        "export" => "export_kit",
        "receipt" => "receipts",
        "hooks" => "hooks",
        "selfcheck" => "fast_gate",
        "openbsd-tier" => "openbsd_tier",
        "coverage" => "coverage_map",
        "predict" => "predict",
        "falsify" => "falsify",
        "taste" => "taste",
        "reconcile" => "reconcile",
        "prune" => "prune",
        "precedent" => "precedent",
        "trust" => "trust",
        "court" => "court",
        "scars" => "scars",
        "pedagogy" => "pedagogy",
        "capability" => "capability",
        "sunset" => "sunset",
        "kinds" => "kinds_registry",
      }.freeze

      class << self
        include Base

        def run(argv)
          command = argv.first.to_s
          # Hooks install themselves on first contact: any bin/master agent
          # invocation is a clone's cheapest proof loop, so the gate that the
          # constitution runs on every landing stops depending on an operator
          # remembering `bin/operator hooks`.
          require_relative "hooks"
          if %w[hooks].include?(command)
            require_relative "hooks"
            return Master::Agent::Hooks.run(argv.drop(1))
          end
          Hooks.ensure_installed(root: repo_root) if command != "help"

          file = COMMANDS[command]
          if file.nil?
            emit(help_payload)
            exit(command == "help" || command.empty? ? 0 : 64)
          end

          require_relative file
          module_name = file.split("_").map(&:capitalize).join.sub("Openbsd", "Openbsd")
          klass = Master::Agent.const_get(module_name)
          klass.run(argv.drop(1))
        rescue StandardError => e
          warn "agent: #{e.class}: #{e.message}"
          warn e.backtrace.take(4).join("\n") if ENV["MASTER_AGENT_TRACE"]
          exit 70
        end

        def help_payload
          {
            surface: "bin/master <command> - the zero-dependency agent tier (stdlib only)",
            commands: COMMANDS.keys,
            forms: {
              "scan --bare PATH" => "lexical law corpus over PATH, JSON findings, no bundle",
              "laws [--json ID]" =>
                "one generated index: statement, severity, mode, lifecycle, languages, " \
                "surfaces, path scope, exemptions, fixtures, proved_by",
              "status --agent" =>
                "one union view of every ledger: actionable-now, needs-proof, needs-operator, refused",
              "owns PATH" => "owning law, check, test, callers, PATH_OWNERSHIP entry",
              "receipt ..." =>
                "structured evidence a landing can hand back; validates and names the cheapest next measurement",
              "selfcheck --fast" => "the seconds-scale self-consistency gate, not the 48-minute one",
              "orient" => "the first hour: five trees, one real finding, one receipt that validates",
            },
          }
        end
      end
    end
  end
end

# Direct invocation for hosts without the checkout wired to bin/master:
#   ruby MASTER/lib/agent/agent_cli.rb scan --bare PATH
if $PROGRAM_NAME.end_with?("agent_cli.rb") && !$PROGRAM_NAME.include?("bin/master")
  exit Master::Agent::CLI.run(ARGV)
end
