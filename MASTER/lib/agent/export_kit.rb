# frozen_string_literal: true

# bin/master export --laws DIR - a constitution that travels.
#
# The laws are called transferable engineering knowledge; this makes that
# literal. The kit drops into a foreign tree with its own tokens file and
# its own ownership ledger: the law catalogue, the bare scanner and its
# loader, the receipt vocabulary, the fixtures, and a universality report
# naming which laws are universal and which are house-specific - so an
# external pilot is an afternoon of adoption, not a bespoke engagement.

require "fileutils"
require_relative "fast_gate"

module Master
  module Agent
    module ExportKit
      extend Base

      class << self
        include Base

        def run(argv)
          out = argv.index("--laws") ? argv[argv.index("--laws") + 1] : nil
          refuse("export", "no --laws DIR given", "a directory to build the kit in, e.g. --laws /tmp/law-kit") if out.nil?

          kit = File.expand_path(out)
          FileUtils.mkdir_p(kit)

          copy_tree(kit)
          universality = write_universality_report(kit)
          write_readme(kit, universality)
          write_tokens_template(kit)
          write_ownership_template(kit)

          emit(
            command: "export --laws",
            kit: kit,
            files: Dir.glob(File.join(kit, "**", "*")).select { |f| File.file?(f) }.size,
            universal_laws: universality[:universal].size,
            house_laws: universality[:house].size,
            next_steps: [
              "edit kit/tokens.yml: the receiving tree names its own owners and paths",
              "run kit/run.sh scan --bare <a directory in the receiving tree>",
              "read kit/UNIVERSALITY.md before adopting a house-specific law",
            ],
          )
          0
        end

        def copy_tree(kit)
          %w[lib/agent data law].each { |d| FileUtils.mkdir_p(File.join(kit, d)) }
          %w[agent_cli.rb bare_law_loader.rb bare_scan.rb law_index.rb receipts.rb fast_gate.rb
             hooks.rb kinds_registry.rb].each do |mod|
            FileUtils.cp(File.join(master_root, "lib", "agent", mod), File.join(kit, "lib", "agent", mod))
          end
          FileUtils.cp(data_path("laws.yml"), File.join(kit, "data", "laws.yml"))
          FileUtils.cp(data_path("law_kinds.yml"), File.join(kit, "data", "law_kinds.yml"))
          index = File.join(master_root, "data", "laws_index.json")
          FileUtils.cp(index, File.join(kit, "data", "laws_index.json")) if File.file?(index)
          fixtures = File.join(master_root, "checks", "data", "law_fixtures.yml")
          FileUtils.cp(fixtures, File.join(kit, "data", "law_fixtures.yml")) if File.file?(fixtures)
          FileUtils.cp(File.expand_path("../../law/lexical.rb", __dir__), File.join(kit, "law", "lexical.rb"))
          # The runner script is the kit's own bin; it binds the copied tree.
          File.write(File.join(kit, "run.sh"), <<~RUN)
            #!/bin/sh
            # The kit's bare entrypoint. Run from the kit's own directory.
            cd "$(dirname "$0")/MASTER" 2>/dev/null || cd "$(dirname "$0")"
            ruby -r./lib/agent/agent_cli.rb -e 'exit Master::Agent::CLI.run(ARGV)' "$@"
          RUN
          FileUtils.chmod(0o755, File.join(kit, "run.sh"))
        end

        # Which laws travel and which are house law. The catalogue's universal
        # flag is the source; where an entry is silent, the default policy
        # (universal_by_default) decides and the report says so.
        def write_universality_report(kit)
          universal = []
          house = []
          catalogue_entries.each do |id, entry|
            next unless entry.is_a?(Hash)

            flagged = entry.key?("universal") ? entry["universal"] : catalogue.fetch("universal_by_default", true)
            (flagged ? universal : house) << { id:, severity: entry["severity"],
                                               why: entry.key?("universal") ? "flagged in the catalogue" : "default policy" }
          end
          File.write(File.join(kit, "UNIVERSALITY.md"), <<~MD)
            # Universality report

            Generated from MASTER/data/laws.yml law_catalogue at #{FastGate.head_revision}.

            - #{universal.size} laws travel: they are universal by flag or by default policy, and
              the receiving tree may adopt them as written.
            - #{house.size} laws are house law: they judge surfaces, names or policies this
              checkout owns. Adopt one only after reading its statement here and deciding
              the same way this tree did - the kit carries the law, the receiving tree
              must supply its own reason.

            ## House laws

            #{house.map { |l| "- #{l[:id]} (#{l[:severity]})" }.first(40).join("\n")}
          MD
          { universal:, house: }
        end

        def write_readme(kit, universality)
          File.write(File.join(kit, "README.md"), <<~MD)
            # The law kit

            A self-contained constitution: the bare scanner, the lexical law corpus,
            the receipt vocabulary, the kind registry, and the catalogue they all
            read. No bundle, no Chrome, no libvips - the same zero-dependency tier
            this tree runs, pointed at a foreign tree.

            Contents: lib/agent (the tier), law/lexical.rb (the corpus), data/
            (laws.yml, kinds, fixtures, the generated index), UNIVERSALITY.md
            (#{universality[:universal].size} travelling laws, #{universality[:house].size} house laws),
            tokens.yml (fill in), ownership.yml (fill in).

            Proof tier first: `./run.sh scan --bare <path>` answers in seconds.
            The heavier proof lanes stay with the full runtime this kit came from.
          MD
        end

        def write_tokens_template(kit)
          File.write(File.join(kit, "tokens.yml"), <<~YML)
            # The receiving tree's own tokens. A law travels; the names it
            # judges belong to the tree that adopts it.
            schema: 1
            tree: "<receiving tree name>"
            owners:
              governance: "<who owns the law here>"
              operator: "<who rules on taste and refusals>"
            paths:
              lib: "<where the receiving tree's code lives>"
              excluded: []
          YML
        end

        def write_ownership_template(kit)
          File.write(File.join(kit, "ownership.yml"), <<~YML)
            # Ownership for the receiving tree, in PATH_OWNERSHIP's own shape.
            ownership: {}
              # path:
              #   purpose: what this path is for
              #   risk: low | medium | high
              #   check: the command that proves it
          YML
        end
      end
    end
  end
end
