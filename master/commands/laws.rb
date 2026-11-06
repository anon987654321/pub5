# frozen_string_literal: true

require_relative "../../laws/engine"

module Commands
  # `laws` lists every Law with its lifecycle; `laws census ID` runs one Law
  # over every tracked file and prints the measurement a census row records
  # (files, findings) plus each finding, so a sample can be judged by hand or
  # by an independent model before the operator ratifies enforcement.
  # `laws census --all` runs every advisory Law that scans, one line each.
  class Laws
    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(argv)
      laws = Law.load!
      return list(laws) unless argv.first == "census"

      texts = @world.git("ls-files", "-z").out.split("\0").to_h { |f| [f, @world.read(f).force_encoding("UTF-8").scrub] }
      commit = @world.git("rev-parse", "--short=10", "HEAD").out.strip
      return census_all(laws, texts, commit) if argv[1] == "--all"

      census(Law[argv.fetch(1)], texts, commit, each: true)
      0
    end

    private

    def census(law, texts, commit, each: false)
      files = texts.keys.select { |f| law.applies?(f, texts[f]) }
      findings = files.flat_map { |f| law.scan(texts[f], f) }
      findings += law.scan_tree(texts.keys)
      findings.each { |f| @out.puts "census: #{f}" } if each
      errors = law.errors.size
      @out.puts "census: #{law.id} at #{commit}: files #{files.size}, findings #{findings.size}" \
                "#{", errors #{errors} (#{law.errors.first})" if errors.positive?}"
      findings
    end

    # Every Law that scans, one line each, then every finding: the
    # measurement a promotion starts from.
    def census_all(laws, texts, commit)
      scanning = laws.reject { |law| law.broken || !law.deterministic? || law.enforced? }
      found = scanning.to_h { |law| [law, census(law, texts, commit)] }
      found.each_value { |findings| findings.each { |f| @out.puts "finding: #{f}" } }
      @out.puts "census: #{scanning.size} advisory Laws scanned, #{found.count { |_, f| f.any? }} with findings, " \
                "#{found.values.sum(&:size)} findings, #{scanning.count { |l| l.errors.any? }} raised"
      0
    end

    def list(laws)
      laws.each { |law| @out.puts "#{law.id} #{law.lifecycle} #{law.severity}" }
      @out.puts "laws: #{laws.size} (#{laws.count(&:enforced?)} enforced)"
      0
    end
  end
end
