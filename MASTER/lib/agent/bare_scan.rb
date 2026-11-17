# frozen_string_literal: true

# bin/master scan --bare PATH [--laws ID,ID2] [--text]
#
# The zero-dependency proof tier. One stdlib-only entry that runs the
# detect-regex (lexical) law corpus over PATH under any Ruby 3.3+ with no
# bundle, no Chrome and no libvips, and emits JSON findings. The session that
# wished for this approximated the scanner with greps because the real thing
# meant building Ruby, five bundles, Chrome and libvips on a host that kept
# dying. Measuring before declaring done should be the easy path; this is
# that path. Rendered proof stays deferred until actually requested.

require_relative "bare_law_loader"

# The lexical corpus parses Ruby with Prism (bundled with Ruby 3.3+); the
# corpus itself is loaded verbatim and never re-typed here.
require "prism"

module Master
  module Agent
    module BareScan
      extend Base

      DEFAULT_CORPUS = "lexical"

      class << self
        include Base

        def run(argv)
          options = { format: "json", corpus: DEFAULT_CORPUS, laws: nil }
          parser = OptionParser.new do |opts|
            opts.banner = "usage: bin/master scan --bare PATH [--laws ID,ID2] [--json|--text] [--corpus NAME]"
            opts.on("--bare", "stdlib-only run; the only mode this tier offers") { options[:bare] = true }
            opts.on("--laws LIST", "restrict to these law ids") { |list| options[:laws] = list.split(",").map(&:strip) }
            opts.on("--corpus NAME",
                    "law file stem: lexical (default), ruby, shell, ...") { |name| options[:corpus] = name }
            opts.on("--text", "human lines instead of JSON") { options[:format] = "text" }
            opts.on("--json", "JSON (default)") { options[:format] = "json" }
          end
          parser.parse!(argv)
          path = argv.shift
          refuse("scan --bare", "no PATH given",
                 "a file or directory to judge, e.g. bin/master scan --bare lib/agent") if path.nil?

          corpus = load_corpus(options[:corpus])
          files = discover(path)
          refuse("scan --bare", "PATH #{path} matches no readable file",
                 "an existing file or directory under the checkout") if files.empty?

          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          findings = files.flat_map { |file| corpus.scan_file(file, only: options[:laws]) }
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)

          payload = {
            command: "scan --bare",
            path:,
            corpus: options[:corpus],
            ruby: RUBY_VERSION,
            bundle: false,
            files_scanned: files.size,
            laws_applied: corpus.laws.keys.size,
            laws_skipped: corpus.skipped,
            findings_count: findings.size,
            findings:,
            elapsed_s: elapsed,
            note: "lexical corpus only; semantic and visual proof stay deferred until requested",
          }
          if options[:format] == "text"
            findings.each { |f| puts "#{f[:file] || path}:#{f[:law]}:#{f[:line]} #{f[:message]}" }
            puts "#{findings.size} findings over #{files.size} files, #{corpus.laws.keys.size} laws, #{elapsed}s"
          else
            emit(payload)
          end
          findings.empty? ? 0 : 1
        end

        def load_corpus(stem)
          law_file = File.expand_path("../../law/#{stem}.rb", __dir__)
          unless File.file?(law_file)
            refuse("scan --bare", "corpus #{stem} is not a law file", "one of the file stems in MASTER/law/")
          end
          BareCorpus.new([law_file])
        end

        def discover(path)
          full = File.expand_path(path)
          files = if File.directory?(full)
                    Dir.glob(File.join(full, "**", "*")).select { |f| File.file?(f) && readable_source?(f) }
                  elsif File.file?(full)
                    [full]
                  else
                    []
                  end
          files.grep_v(%r{/\.git/}).sort
        end

        def readable_source?(file)
          return false if File.size(file) > 4 * 1024 * 1024

          File.readable?(file)
        end
      end
    end
  end
end
