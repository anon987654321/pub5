# frozen_string_literal: true

require_relative "../../laws/engine"

module Commands
  # A per-Law measurement from one census run. A census is evidence for
  # review; it is not, by itself, a promotion or an enforcement decision.
  Measurement = Data.define(:files, :findings, :errors)

  # `laws` lists every Law with its lifecycle; `laws census ID` runs one Law
  # over every tracked file and prints the measurement a census row records
  # (files, findings) plus each finding, so a sample can be judged by hand or
  # by an independent model before the operator ratifies enforcement.
  # `laws census --all` reports every loaded Law, including those that cannot
  # yet be scanned, so a partial census cannot look like a complete audit.
  class Laws
    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(argv)
      laws = Law.load!
      return list(laws) unless argv.first == "census"
      return usage unless argv[1]

      texts = @world.git("ls-files", "-z").out.split("\0").to_h do |file|
        [file, @world.read(file).force_encoding("UTF-8").scrub]
      end
      commit = @world.git("rev-parse", "--short=10", "HEAD").out.strip
      return census_all(laws, texts, commit) if argv[1] == "--all"

      census(Law[argv.fetch(1)], texts, commit, each: true)
      0
    end

    private

    def census(law, texts, commit, each: false, report: true)
      files = texts.keys.select { |file| law.applies?(file, texts[file]) }
      findings = files.flat_map { |file| law.scan(texts[file], file) }
      findings += law.scan_tree(texts.keys)
      findings.each { |finding| @out.puts "census: #{finding}" } if each

      errors = law.errors.size
      if report
        error_note = errors.positive? ? ", errors #{errors} (#{law.errors.first})" : ""
        @out.puts "census: #{law.id} at #{commit}: files #{files.size}, findings #{findings.size}#{error_note}"
      end
      Measurement.new(files: files.size, findings:, errors:)
    end

    # A deterministic advisory Law is only a census candidate. It still
    # needs a representative sample, a <=5% false-positive rate and operator
    # ratification before it may be promoted. Every other lifecycle is
    # printed with an explicit reason it was not measured.
    def census_all(laws, texts, commit)
      candidates = laws.select { |law| census_candidate?(law) }
      measurements = candidates.to_h do |law|
        [law, census(law, texts, commit, report: false)]
      end

      laws.each do |law|
        measurement = measurements[law]
        status = measurement && measurement.errors.positive? ? "CENSUS_ERROR" : readiness(law)
        details = if measurement
                    " files=#{measurement.files} findings=#{measurement.findings.size} errors=#{measurement.errors}"
                  else
                    " census=NOT_RUN"
                  end
        @out.puts "law: #{law.id} #{status} kind=#{law.policy.fetch('kind', 'unknown')}#{details}"
        measurement&.findings&.each { |finding| @out.puts "finding: #{finding}" }
      end

      measured = measurements.values
      findings = measured.sum { |measurement| measurement.findings.size }
      errors = measured.sum(&:errors)
      with_findings = measured.count { |measurement| measurement.findings.any? }
      @out.puts "census: laws #{laws.size}, enforced #{laws.count(&:enforced?)}, " \
                "broken #{laws.count { |law| broken?(law) }}, " \
                "unported #{laws.count { |law| law.policy['unported'] }}, " \
                "retired #{laws.count { |law| law.lifecycle == 'retired' }}, " \
                "census candidates #{candidates.size}, model review #{laws.count { |law| readiness(law) == 'MODEL_REVIEW' }}, " \
                "human review #{laws.count { |law| readiness(law) == 'HUMAN_REVIEW' }}"
      @out.puts "census: measured #{measured.size}, #{with_findings} with findings, #{findings} findings, #{errors} scanner errors at #{commit}"
      @out.puts "census: CENSUS_CANDIDATE is not ENFORCED; sampling, false-positive review and operator ratification remain required"
      0
    end

    def census_candidate?(law)
      law.lifecycle == "advisory" && !broken?(law) && !law.policy["unported"] && law.deterministic?
    end

    def readiness(law)
      return "BROKEN" if broken?(law)
      return "UNPORTED" if law.policy["unported"]
      return "RETIRED" if law.lifecycle == "retired"
      return "ENFORCED" if law.enforced?
      return "CENSUS_CANDIDATE" if law.deterministic?
      return "MODEL_REVIEW" if law.semantic?

      "HUMAN_REVIEW"
    end

    def broken?(law) = law.broken || law.policy["broken"]

    def list(laws)
      laws.each { |law| @out.puts "#{law.id} #{law.lifecycle} #{law.severity}" }
      @out.puts "laws: #{laws.size} (#{laws.count(&:enforced?)} enforced)"
      0
    end

    def usage
      @out.puts "usage: bin/master laws [census ID|census --all]"
      64
    end
  end
end
