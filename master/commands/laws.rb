# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../laws/engine"
require_relative "../models/dispatch"

module Commands
  class Laws
    def initialize(world:, context:, out: $stdout)
      @world = world
      @context = context
      @out = out
    end

    def call(argv)
      laws = Law.load!
      case argv.first
      when "review" then semantic_review(laws, argv.drop(1))
      when "census" then census_command(laws, argv.drop(1))
      when nil then list(laws)
      else usage
      end
    end

    private

    def semantic_review(laws, argv)
      id = argv.shift
      return usage unless id && argv.any?
      law = laws.find { |item| item.id.to_s.casecmp?(id) }
      raise ArgumentError, "unknown Law #{id}" unless law
      raise ArgumentError, "#{id} is not a semantic Law with a review rubric" unless law.semantic?

      items = Law::SemanticReview.evidence(@world, argv)
      prompt = Law::SemanticReview.prompt(law, items)
      dispatch = Models::Dispatch.build(@world, knobs: Core::Knobs.default,
                                        say: ->(line) { @out.puts "review: #{line}" })
      reply = dispatch.ask(prompt, task: "review", max_tokens: 2_500)
      result = Law::SemanticReview.parse(reply.text, valid_ids: items.map(&:id))
      receipt = {
        law: law.id.to_s, decision: result.decision.to_s, confidence: result.confidence,
        reviewer: reply.model,
        evidence: items.map { |item| { id: item.id, path: item.path, sha256: item.digest } },
        cited: result.evidence.map(&:id), counterexamples: result.counterexamples,
        missing_evidence: result.missing_evidence,
        rationale_digest: Digest::SHA256.hexdigest(result.rationale)
      }
      @world.ledger.append(:law_review, **receipt)
      @out.puts JSON.pretty_generate(receipt.merge(rationale: result.rationale, evidence: result.evidence.map(&:to_h)))
      { pass: 0, fail: 1, abstain: 3 }.fetch(result.decision)
    rescue Law::Invalid, ArgumentError, Core::Refusal, Models::Dispatch::Exhausted => error
      @out.puts "review: #{error.class}: #{error.message}"
      3
    end

    def census_command(laws, argv)
      return usage unless argv.first
      texts = @world.git("ls-files", "-z").out.split("\0").to_h do |file|
        [file, @world.read(file).force_encoding("UTF-8").scrub]
      end
      commit = @world.git("rev-parse", "--short=10", "HEAD").out.strip
      return census_all(laws, texts, commit) if argv.first == "--all"

      census(Law[argv.fetch(0)], texts, commit, each: true)
      0
    end

    def census(law, texts, commit, each: false)
      files = texts.keys.select { |file| law.applies?(file, texts[file]) }
      findings = files.flat_map { |file| law.scan(texts[file], file) }
      findings += law.scan_tree(texts.keys)
      findings.each { |finding| @out.puts "census: #{finding}" } if each
      errors = law.errors.size
      note = errors.positive? ? ", errors #{errors} (#{law.errors.first})" : ""
      @out.puts "census: #{law.id} at #{commit}: files #{files.size}, findings #{findings.size}#{note}"
      findings
    end

    def census_all(laws, texts, commit)
      candidates = laws.select do |law|
        law.lifecycle == "advisory" && !law.broken && !law.policy["unported"] && law.deterministic?
      end
      measurements = candidates.to_h { |law| [law, census(law, texts, commit)] }
      laws.each do |law|
        measurement = measurements[law]
        status = if law.broken || law.policy["broken"] then "BROKEN"
                 elsif law.policy["unported"] then "UNPORTED"
                 elsif law.lifecycle == "retired" then "RETIRED"
                 elsif law.enforced? then "ENFORCED"
                 elsif law.deterministic? then "CENSUS_CANDIDATE"
                 elsif law.semantic? then "MODEL_REVIEW"
                 else "HUMAN_REVIEW"
                 end
        @out.puts "law: #{law.id} #{status}#{measurement ? " files=#{texts.size} findings=#{measurement.size}" : " census=NOT_RUN"}"
      end
      @out.puts "census: #{laws.size} laws, #{candidates.size} deterministic census candidates, " \
                "#{laws.count { |law| law.policy['unported'] }} unported, #{laws.count { |law| law.broken || law.policy['broken'] }} broken"
      0
    end

    def list(laws)
      laws.each { |law| @out.puts "#{law.id} #{law.lifecycle} #{law.severity}" }
      @out.puts "laws: #{laws.size} (#{laws.count(&:enforced?)} enforced)"
      0
    end

    def usage
      @out.puts "usage: bin/master laws [census --all|census ID|review SEMANTIC_LAW EVIDENCE_FILE ...]"
      64
    end
  end
end
