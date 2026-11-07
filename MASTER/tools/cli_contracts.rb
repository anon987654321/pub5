# frozen_string_literal: true

# CLI contracts: what each MASTER entrypoint answers to --help, recorded so a
# port can be checked against them. Third piece of the pub5 acceptance harness
# (TODO.md, current-revision acceptance): pub5's core keeps the same command surface, and
# its help must not silently rename a verb the operator learned.
#
#   ruby MASTER/tools/cli_contracts.rb record
#   ruby MASTER/tools/cli_contracts.rb check [--root PATH]
#
# One contract per entrypoint: the --help exit code, the first non-empty line,
# the command tokens the usage lines name, and a SHA-256 of the digit-normalised
# help text. Every command runs read-only here: --help is an answer, not work.

require "digest"
require "open3"
require "yaml"

module CliContracts
  ROOT = File.expand_path("../..", __dir__)
  REPOSITORY_NAME = "pub5".freeze
  DATA = File.join(ROOT, "MASTER", "checks", "data", "cli_contracts.yml")
  ENTRYPOINTS = %w[MASTER/bin/master MASTER/bin/operator].freeze
  TIMEOUT = 30

  module_function

  # ruby -x executes past the first non-Ruby lines (bin/operator carries a shell
  # wrapper), and needs no exec bit, so one runner answers for both shapes. The
  # shell's bundle environment is dropped: a help answer is a bare Ruby question.
  CLEAN_ENV = { "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil, "RUBYOPT" => nil, "BUNDLER_ORIG_PATH" => nil }.freeze

  def run(root, path)
    out, err, status = Open3.capture3(CLEAN_ENV, RbConfig.ruby, "-x", path, "--help", chdir: root)
    [status.exitstatus, out, err]
  rescue StandardError => e
    [nil, "", e.message]
  end

  def normalise(text) = text.gsub(/\d+/, "N")

  def tokens(root, help_text)
    help_text.lines.filter_map do |line|
      line = line.sub(/\A\s*(helpN at \w+: |helpN: )/, "")
      match = line.match(/\Abin\/[a-z-]+ (\S+)/) # "bin/operator check [--scan-only] ..."
      next unless match

      match[1].gsub('"', "")
    end.compact.uniq.sort
  end

  # One stream: bin/master writes help to stdout and bin/operator to stderr,
  # so the contract reads both and the head is the first non-empty line either
  # carries. The recorded exit is whatever the entrypoint answers --help with,
  # including a usage refusal (bin/operator answers 2) - the contract pins it.
  def contract(root, path)
    code, out, err = run(root, path)
    text = normalise(out + err)
    {
      "exit" => code,
      "head" => text.lines.find { |line| !line.strip.empty? }&.sub(/\A(helpN at \w+: |helpN: )/, "")&.chomp,
      "tokens" => tokens(root, text),
      "digest" => Digest::SHA256.hexdigest(text),
    }
  end

  def record
    contracts = ENTRYPOINTS.to_h { |path| [path, contract(ROOT, path)] }
    File.write(DATA, YAML.dump({ "schema" => 1, "root" => REPOSITORY_NAME, "entrypoints" => contracts }))
    contracts
  end

  def compare(want, got)
    fields = (want.keys | got.keys).reject { |key| want[key] == got[key] }
    return unless fields.any?

    fields.map { |key| "#{key}: #{want[key].inspect} -> #{got[key].inspect}" }.join("; ")
  end

  # The entrypoint names are recorded at pub4's spelling; a port tree is the
  # same shape at its own spelling, so check resolves each name on the target
  # root - recorded path first, then the lowercase tree and then its root
  # bin (pub5 flattens MASTER/bin/* onto bin/*) - and names the path the
  # answer came from. A tree that carries none keeps the recorded name, so
  # the run still surfaces the loader's refusal, never silence.
  def resolve(root, path)
    [path,
     path.sub(/\AMASTER\//, "master/"),
     path.sub(/\A(?:MASTER|master)\//, "")]
      .find { |name| File.file?(File.join(root, name)) } || path
  end

  def check(root)
    recorded = YAML.load_file(DATA).fetch("entrypoints")
    ENTRYPOINTS.filter_map do |path|
      found = resolve(root, path)
      got = contract(root, found)
      detail = compare(recorded.fetch(path, {}), got)
      detail = "#{found}: #{detail}" if detail && found != path
      [path, detail] if detail
    end
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV.first || "check"
  flags = ->(name) { ARGV.include?(name) ? ARGV[ARGV.index(name) + 1] : nil }
  target = flags.call("--root") || CliContracts::ROOT

  if mode == "record"
    contracts = CliContracts.record
    contracts.each { |path, row| puts("#{path}: exit #{row['exit']}, #{row['tokens'].size} tokens") }
    puts "wrote #{CliContracts::DATA.delete_prefix("#{CliContracts::ROOT}/")}"
  else
    differences = CliContracts.check(target)
    differences.each { |path, detail| puts "#{path}  #{detail}" }
    puts differences.empty? ? "every entrypoint matches its contract (#{target})" : "#{differences.size} entrypoint(s) differ"
    exit(differences.empty? ? 0 : 1)
  end
end
