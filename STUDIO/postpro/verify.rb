#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify that a graded frame can be replayed from its receipt.
#
# Every grade sidecar (postpro.grade.v2) records the preset dealt to the
# frame, the seed, the code version digest and the input and output hashes.
# That is a reproducibility CLAIM; this tool is the check. It re-runs the
# recorded grade in a scratch directory and compares the result to the
# recorded output hash:
#
#   ruby STUDIO/postpro/verify.rb path/to/postpro_frame_v1.json --json
#
# Verdicts: VERIFIED (byte-identical replay), MISMATCH (same code, different
# bytes - the grade is not deterministic and the receipt's promise fails),
# VERSION_DRIFT (the code digest changed since the grade ran; checkout the
# matching commit to replay), NOT_VERIFIABLE (receipt incomplete, or the
# input no longer holds the recorded bytes). A MISMATCH is a finding about
# determinism, not about taste.

require "digest"
require "fileutils"
require "json"
require "optparse"
require "rbconfig"
require "tmpdir"
require_relative "../replicate/subprocess"

module Postpro
  module Verify
    DIR = File.expand_path(__dir__).freeze
    ENTRY = File.join(DIR, "postpro.rb").freeze
    ANALOG_CORE = File.expand_path("../dilla/analog_core.rb", DIR).freeze
    REPLAY_TIMEOUT = 600

    class Error < StandardError; end

    module_function

    # The same digest sidecars.rb stamps into every receipt: the bytes of
    # postpro.rb, its lib and the analog core. Recomputed here so verify can
    # run without loading the grading stack; if this and GRADE_VERSION ever
    # disagree, receipts report VERSION_DRIFT - a safe failure that says
    # "cannot confirm", never a false MISMATCH.
    def grade_version
      files = [ENTRY, ANALOG_CORE, *Dir[File.join(DIR, "*.rb"), File.join(DIR, "lib", "*.rb")].sort].uniq
      Digest::SHA256.hexdigest(files.map { |path| File.binread(path) }.join)[0, 12]
    end

    # Pure verdict, so the state mapping is testable without grading anything.
    def verdict(receipt_version:, current_version:, byte_match:)
      return "NOT_VERIFIABLE" if receipt_version.to_s.empty?
      return "VERSION_DRIFT" if receipt_version != current_version

      byte_match ? "VERIFIED" : "MISMATCH"
    end

    def verify(sidecar_path)
      raise Error, "sidecar is missing or a symlink" unless File.file?(sidecar_path) && !File.symlink?(sidecar_path)

      receipt = JSON.parse(File.read(sidecar_path, encoding: "UTF-8"))
      raise Error, "not a grade receipt" unless receipt["schema"] == "postpro.grade.v2"

      preset = receipt["preset"].to_s
      seed = receipt["seed"]
      input = receipt["input"].to_s
      expected_input = receipt["input_sha256"].to_s
      expected_output = receipt["output_sha256"].to_s
      if preset.empty? || seed.nil? || expected_output.empty?
        return { "state" => "NOT_VERIFIABLE", "reason" => "receipt lacks preset, seed or output hash" }
      end
      unless File.file?(input) && !File.symlink?(input) && Digest::SHA256.file(input).hexdigest == expected_input
        return { "state" => "NOT_VERIFIABLE", "reason" => "input no longer holds the bytes the receipt recorded" }
      end

      replayed = replay(input, preset, seed)
      state = verdict(
        receipt_version: receipt["grade_version"].to_s,
        current_version: grade_version,
        byte_match: Digest::SHA256.file(replayed).hexdigest == expected_output
      )
      {
        "schema" => "postpro.verify.v1",
        "state" => state,
        "sidecar" => File.basename(sidecar_path),
        "preset" => preset,
        "seed" => seed,
        "receipt_grade_version" => receipt["grade_version"],
        "current_grade_version" => grade_version,
        "provider_calls" => 0,
      }
    rescue JSON::ParserError => error
      { "state" => "NOT_VERIFIABLE", "reason" => "sidecar is not valid JSON: #{error.message}" }
    ensure
      FileUtils.remove_entry(@scratch) if @scratch && File.directory?(@scratch)
    end

    # Re-run the recorded grade in a private scratch directory: the dealt
    # preset from the receipt (not a re-dealt one), the recorded seed, the
    # recorded input bytes.
    def replay(input, preset, seed)
      @scratch = Dir.mktmpdir("postpro-verify-")
      File.chmod(0o700, @scratch)
      copy = File.join(@scratch, "replay#{File.extname(input)}")
      FileUtils.cp(input, copy)
      File.chmod(0o600, copy)

      stdout, stderr, status = Studio::Subprocess.capture3(
        { "POSTPRO_SEED" => seed.to_s }, RbConfig.ruby, ENTRY,
        "--preset", preset, "--count", "1", copy, timeout: REPLAY_TIMEOUT
      )
      raise Error, "postpro replay failed: #{[stdout, stderr].compact.join("\n").lines.last.to_s.strip}" unless status.success?

      ext = File.extname(copy)
      stem = File.basename(copy, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
      output = Dir[File.join(@scratch, "postpro_#{stem}_*_v1#{ext}")].max_by { |file| File.mtime(file) }
      raise Error, "postpro replay produced no output" unless output

      output
    end

    def run_cli(argv)
      options = { sidecar: nil, json: false }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby STUDIO/postpro/verify.rb SIDECAR [--json]"
        parser.on("--json", "Print the full machine-readable receipt") { options[:json] = true }
        parser.on("-h", "--help", "Show this help") { puts parser; return 0 }
      end.parse!(argv)
      options[:sidecar] = argv.first

      if options[:sidecar].to_s.empty?
        warn "a grade sidecar path is required"
        return 64
      end

      receipt = verify(File.expand_path(options[:sidecar]))
      if options[:json]
        puts JSON.pretty_generate(receipt)
      else
        puts "verify: #{receipt.fetch("state")}#{receipt["reason"] ? " - #{receipt.fetch("reason")}" : ""}"
      end
      receipt.fetch("state") == "VERIFIED" ? 0 : 1
    rescue Error, SystemCallError, IOError => error
      warn "BLOCKED: #{error.class}: #{error.message}"
      2
    end
  end
end

exit Postpro::Verify.run_cli(ARGV) if $PROGRAM_NAME == __FILE__
