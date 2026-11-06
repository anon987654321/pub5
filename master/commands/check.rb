# frozen_string_literal: true

require_relative "../../laws/engine"

module Commands
  # The gate: every file parses, no enforced Law has a finding, the tests
  # pass. `--staged` judges the bytes in the index (what the commit will
  # hold), not the working tree, so an unstaged fix cannot hide a staged
  # break. Output is one dmesg-style line per stage. A stage that measured
  # nothing (no files, no test summary) says NOT_RUN and fails: a gate that
  # read nothing must not pass.
  class Check
    STAGES = %i[parse laws tests].freeze

    def initialize(world:, context:, out: $stdout)
      @world = world
      @context = context
      @out = out
    end

    def stages = STAGES

    def call(argv)
      @staged = argv.include?("--staged")
      files = @staged ? staged_files : tracked_files
      ok = stages.map { |stage| stage == :tests ? tests : send(stage, files) }.all?
      @out.puts "#{self.class.name.split('::').last.downcase}: #{ok ? 'ok' : 'FAILED'}"
      ok ? 0 : 1
    end

    private

    def tracked_files
      @world.git("ls-files", "-z", "--cached", "--others", "--exclude-standard").out.split("\0")
            .select { |f| File.file?(File.join(@world.manifest.root, f)) }
    end

    def staged_files = @world.git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR").out.split("\0")

    def text(file)
      @staged ? @world.git("show", ":#{file}").out : @world.read(file).force_encoding("UTF-8")
    end

    def kind(file) = Core::ParseGate.kind(File.join(@world.manifest.root, file))

    def parse(files)
      judged = files.select { |f| kind(f) }
      if judged.empty? && !@staged
        @out.puts "parse: NOT_RUN (no Ruby, YAML, JSON or ERB files found)"
        return false
      end

      bad = judged.filter_map { |f| (problem = Core::ParseGate.problem(kind(f), text(f))) && [f, problem] }
      bad.each { |f, problem| @out.puts "parse: #{f}: #{problem}" }
      @out.puts "parse: #{judged.size} files, #{bad.size} broken"
      bad.empty?
    end

    # Only enforced Laws judge here: an advisory Law cannot fail a push, and
    # the ~800 imported from pub4 cost minutes over the tree. Their
    # findings are measured by `bin/master laws census`.
    def laws(files)
      laws = Law.load!
      enforced = laws.select(&:enforced?)
      findings = files.flat_map { |f| enforced.flat_map { |law| law.scan(text(f).scrub, f) } }
      findings.each { |f| @out.puts "law: #{f}" }
      @out.puts "laws: #{laws.size} loaded (#{laws.count(&:broken)} broken), fixtures proved; #{files.size} files, " \
                "#{findings.size} enforced findings; advisory not scanned here (bin/master laws census)"
      findings.empty?
    rescue Law::Invalid => e
      e.message.each_line { |line| @out.puts "laws: #{line.chomp}" }
      @out.puts "laws: NOT_RUN (the Laws did not load)"
      false
    end

    def tests
      run = @world.exec(RbConfig.ruby, "test/run.rb", timeout: 600)
      summary = run.out.lines.grep(/\d+ runs, \d+ assertions/).last.to_s.strip
      @out.print(run.out, run.err) unless run.ok?
      @out.puts "test: #{summary.empty? ? 'NOT_RUN (no test summary)' : summary}#{' (timed out)' if run.timed_out}"
      run.ok? && !summary.empty? && !summary.start_with?("0 runs")
    end
  end

  # `bin/master lint`: the parse gate and the enforced Laws, without tests.
  class Lint < Check
    def stages = %i[parse laws]
  end

  # `bin/master test`: the minitest suites alone.
  class Test < Check
    def stages = %i[tests]
  end
end
