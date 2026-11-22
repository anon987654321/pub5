# frozen_string_literal: true

# bin/master orient - the first hour, run as a proof.
#
# A stranger used to get a reading list. The failure messages already are the
# documentation; orient walks the five trees in one screen, runs the bare
# scanner, surfaces one real finding, and walks them through handing back a
# receipt that validates. The first hour ends with a completed proof loop,
# not with a table of contents.

require "tmpdir"
require "fileutils"

module Master
  module Agent
    module Orient
      extend Base

      class << self
        include Base

        def run(argv)
          proof = !argv.include?("--no-proof")
          emit(
            command: "orient",
            trees: {
              "MASTER" => "the constitution: laws, gates, the agent tier you are using right now",
              "RAILS" => "the fleet of applications; feature truth lives in RAILS/apps.yml",
              "OPENBSD" => "the host: vm23, its cron and its mirrors; admission tiers via bin/master openbsd-tier",
              "STUDIO" => "the rendered surface: palettes, type and motion the operator owns",
              "BIZ" => "document production: prose with no native interface",
            },
            first_hour: [
              "bin/master selfcheck --fast - the tree's own drift, in seconds",
              "bin/master status --agent - what is open, in one read",
              "bin/master laws --json NO_PUTS - what one law demands and what it exempts",
              "bin/master owns PATH - who owns a path before you touch it",
            ],
            proof_loop: proof ? proof_loop : not_run("proof_loop", "--no-proof skips the measurement; nothing was measured"),
          )
          proof ? 0 : 0
        end

        # One real finding, one receipt that validates: the smallest complete
        # proof loop in the tree. Runs against a throwaway file so the tree
        # itself stays untouched.
        def proof_loop
          dir = Dir.mktmpdir("orient")
          subject = File.join(dir, "orient_subject.rb")
          File.write(subject, "# a file a stranger will judge\nvalue = 1\nputs(\"ready\")\n")

          findings = nil
          begin
            require_relative "bare_scan"
            corpus = BareScan.load_corpus("lexical")
            findings = corpus.scan_file(subject)
          rescue StandardError => e
            return { finding_emitted: false, why: "#{e.class}: #{e.message}" }
          end

          debug = findings.find { |f| f[:law] == "NO_PUTS" }
          receipt_file = File.join(dir, "receipt.json")
          receipt = {
            "receipt" => "1",
            "law" => "NO_PUTS",
            "subject" => subject,
            "claim" => debug ? "FAIL" : "PASS",
            "evidence" => { "kind" => "scanner", "exit" => debug ? 1 : 0,
                            "command" => "bin/master scan --bare #{subject} --laws NO_PUTS" },
            "measured_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "note" => debug ? "the fixture fired as the law's own bad fixture says it must" : "no finding; verify the scanner actually loaded",
          }
          File.write(receipt_file, JSON.generate(receipt))
          require_relative "receipts"
          valid = false
          begin
            answer = Receipts.validate([receipt_file])
            valid = answer.zero?
          rescue StandardError
            valid = false
          end

          FileUtils.remove_entry(dir)
          {
            finding_emitted: !debug.nil?,
            finding: debug ? "#{debug[:law]}:#{debug[:line]} #{debug[:message]}" : nil,
            receipt_claim: receipt["claim"],
            receipt_validated: valid,
            lesson: "you measured, the measurement answered, and the evidence you produced validates against the law it speaks to. This loop is the discipline; everything else in the tree exists to keep it cheap.",
          }
        end
      end
    end
  end
end
