# frozen_string_literal: true

module Law
  # One more detector for the same Law, on its own surfaces: DRY over code and
  # DRY over config are one Law with two adapters. A tree adapter's check takes
  # the repository's paths; a file adapter's takes (text, file).
  Adapter = Data.define(:surfaces, :languages, :check, :bad, :good, :example_path) do
    def tree? = surfaces.intersect?(%i[repository_tree directories file_names paths])
  end

  # What a `check` block or adapter runs on: `finding(line:, message:)` builds a hit.
  class Runner
    def finding(line:, message: nil) = { line:, message: }
  end

  class Definition
    EXAMPLE_PATHS = { "ruby" => "example.rb", "yaml" => "example.yml", "json" => "example.json", "erb" => "example.html.erb",
                      "javascript" => "example.js", "css" => "example.css", "shell" => "example.sh",
                      "markdown" => "example.md", "html" => "example.html" }.freeze

    attr_reader :id, :options, :broken, :errors
    attr_accessor :policy

    # A Law whose file or fixtures failed, kept with the failure: it scans
    # nothing and can never be enforced (Policy).
    def self.broken(id, row, error)
      law = new({ id:, scope: :line, tags: [], languages: [], surfaces: [], adapters: [], reads_comments: false }, row)
      law.instance_variable_set(:@broken, "#{error.class}: #{error.message}"[0, 400])
      law
    end

    # A Law under laws/pub4/ was imported unchanged and reads, scans and
    # proves the way pub4 did (laws/pub4/lib/compat.rb).
    def initialize(options, policy = {})
      @options = options.freeze
      @id = options.fetch(:id)
      @policy = policy
      @errors = []
      @pub4 = Pub4::Subject.new(@options, policy) if policy["file"].to_s.start_with?("laws/pub4/") && Law.const_defined?(:Pub4)
    end

    def imported? = !@pub4.nil?

    def [](word) = @options[word]

    def lifecycle = @policy.fetch("lifecycle", "advisory")
    def severity = @policy.fetch("severity", "warning")
    def enforced? = lifecycle == "enforced"
    def instrumented?
      @policy.dig("pub4", "instrument") == "law_instruments" &&
        /\A[A-Z][A-Z0-9_]+\z/.match?(@policy.dig("pub4", "instrument_id").to_s)
    end
    def deterministic? = !!(self[:detect] || self[:check] || self[:detector] || self[:adapters].any? || instrumented?)
    def semantic? = !self[:ask].nil?

    def applies?(file, text = nil)
      return false if @broken
      return @pub4.applies?(Pub4.name(file), Master.language_for(file, text)) if @pub4
      return false if self[:path].is_a?(String) && !file.include?(self[:path])
      return false if self[:path].is_a?(Regexp) && !file.match?(self[:path])

      self[:languages].empty? || self[:languages].include?(Law.language(file, text))
    end

    # Findings for one file's text. A Law that only asks or only states a
    # practice has no deterministic finding to give.
    def scan(text, file)
      return [] unless applies?(file, text)
      return guarded { pub4_hits(text, file) } if @pub4
      return [] if self[:absent] && text.match?(self[:absent])

      guarded do
        hits = main_hits(text, file)
        self[:adapters].reject(&:tree?).each do |a|
          next unless a.languages.empty? || a.languages.include?(Law.language(file, text))

          hits += findings(Runner.new.instance_exec(text, file, &a.check), text, file)
        end
        hits
      end
    end

    def scan_tree(paths)
      return [] if @broken
      return check_law_findings if @policy["kind"] == "check" || instrumented?
      return guarded { @pub4.scan_tree(paths.map { |p| Pub4.name(p) }).map { |h| Finding.new(id, nil, h.line, h.text, h.message) } } if @pub4

      self[:adapters].select(&:tree?).flat_map { |a| findings(Runner.new.instance_exec(paths, &a.check), "", nil) }
    end

    # A check Law delegates to its one registered instrument. The instrument's
    # fourth outcome is preserved: unavailable browser/live preconditions are
    # INCONCLUSIVE, not a synthetic clean result.
    def check_law_findings
      if instrumented?
        label = @policy.dig("pub4", "instrument_id")
        result = Law::CheckRunner.run("law_instruments", env: { "PUB5_LAW_INSTRUMENT_ID" => label })
      else
        label = @policy.dig("pub4", "id")
        result = Law::CheckRunner.run(label)
      end
      case result.status
      when :passed then []
      when :failed
        [Finding.new(id, nil, 1, result.output.to_s.lines.first.to_s.chomp, "registered instrument #{label} failed (exit #{result.exit_code})")]
      when :inconclusive
        @errors << "INCONCLUSIVE: #{label}: #{result.output.to_s.lines.last.to_s.strip[0, 240]}"
        []
      else
        @errors << "ERROR: #{label}: #{result.output.to_s.lines.last.to_s.strip[0, 240]}"
        []
      end
    rescue StandardError => e
      @errors << "ERROR: Law instrument adapter #{id}: #{e.class}: #{e.message}"[0, 300]
      []
    end

    # Every bad fixture must be found and every good one must not, at load.
    def prove!
      proof = self[:proved_by] || @policy["proved_by"]
      if proof
        raise Invalid, "#{id}: proved_by #{proof} does not exist" unless File.file?(File.join(Core::ROOT, proof))
      end
      return @pub4.prove! && self if @pub4

      prove_main! if self[:detect] || self[:check] || self[:detector]
      self[:adapters].each { |a| prove_adapter!(a) }
      self
    end

    private

    # An advisory Law that raises on a real file is a finding about the
    # Law, not a failed gate: the error is kept for the census. An enforced
    # Law that raises stops the gate.
    def guarded
      yield
    rescue StandardError => e
      raise if enforced?

      @errors << "#{e.class}: #{e.message}"[0, 300]
      []
    end

    # pub4 judged a Law file with its own fixtures and detector lines
    # blanked (Law.conduct), and every file under its pub4 name.
    def pub4_hits(text, file)
      read = file.start_with?("laws/") ? Pub4.conduct(text) : text
      lines = text.lines
      @pub4.scan(read, file: Pub4.name(file), language: Master.language_for(file, text)).map do |hit|
        Finding.new(id, file, hit.line, lines[hit.line - 1].to_s.chomp, hit.message)
      end
    end

    def main_hits(text, file)
      if self[:check]
        findings(Runner.new.instance_exec(text, file, &self[:check]), text, file)
      elsif self[:detector]
        findings(self[:detector].new.check(text, path: file), text, file)
      elsif self[:detect] && self[:scope] == :file
        self[:detect].call(text) ? [Finding.new(id, file, 1, text[/.*/].to_s, nil)] : []
      elsif self[:detect]
        line_hits(text, file)
      else
        []
      end
    end

    def line_hits(text, file)
      comment = COMMENT[Law.language(file, text)]
      text.each_line.with_index(1).filter_map do |line, number|
        next if line.match?(INTENTIONAL)
        next if comment && !self[:reads_comments] && line.match?(comment)

        Finding.new(id, file, number, line.chomp, nil) if self[:detect].call(line)
      end
    end

    def findings(hits, text, file)
      lines = text.lines
      Array(hits).map do |hit|
        line = hit.fetch(:line, 1).to_i
        Finding.new(id, hit.fetch(:file, file), line, lines[line - 1].to_s.chomp, hit[:message])
      end
    end

    def example_path
      self[:example_path] || EXAMPLE_PATHS.fetch(self[:languages].first || "ruby")
    end

    def prove_main!
      raise Invalid, "#{id}: example path #{example_path} is outside this Law's path" unless applies?(example_path)

      Array(self[:bad]).each do |bad|
        bad = bad.call if bad.respond_to?(:call)
        raise Invalid, "#{id}: bad fixture not found: #{bad.inspect[0, 120]}" if main_hits(bad, example_path).empty?
      end
      Array(self[:good]).each do |good|
        good = good.call if good.respond_to?(:call)
        hit = main_hits(good, example_path).first
        raise Invalid, "#{id}: good fixture flagged: #{hit}" if hit
      end
    end

    def prove_adapter!(adapter)
      run = if adapter.tree?
              ->(input) { Array(Runner.new.instance_exec(input, &adapter.check)) }
            else
              ->(input) { Array(Runner.new.instance_exec(input, adapter.example_path || example_path, &adapter.check)) }
            end
      raise Invalid, "#{id}: adapter #{adapter.surfaces.join(',')} misses its bad fixture" if run.call(adapter.bad).empty?
      raise Invalid, "#{id}: adapter #{adapter.surfaces.join(',')} flags its good fixture" if run.call(adapter.good).any?
    end
  end
end
