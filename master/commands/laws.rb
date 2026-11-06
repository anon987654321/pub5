# frozen_string_literal: true

require_relative "../../laws/engine"

module Commands
  # `laws` lists every Law with its lifecycle; `laws census ID` runs one Law
  # over every tracked file and prints the measurement a census row records
  # (files, findings) plus each finding, so a sample can be judged by hand or
  # by an independent model before the operator ratifies enforcement.
  class Laws
    def initialize(world:, context:, out: $stdout)
      @world = world
      @out = out
    end

    def call(argv)
      laws = Law.load!
      return list(laws) unless argv.first == "census"

      law = Law[argv.fetch(1)]
      texts = @world.git("ls-files", "-z").out.split("\0").to_h { |f| [f, @world.read(f).force_encoding("UTF-8").scrub] }
      files = texts.keys.select { |f| law.applies?(f, texts[f]) }
      findings = files.flat_map { |f| law.scan(texts[f], f) }
      findings.each { |f| @out.puts "census: #{f}" }
      commit = @world.git("rev-parse", "--short=10", "HEAD").out.strip
      @out.puts "census: #{law.id} at #{commit}: files #{files.size}, findings #{findings.size}"
      0
    end

    private

    def list(laws)
      laws.each { |law| @out.puts "#{law.id} #{law.lifecycle} #{law.severity}" }
      @out.puts "laws: #{laws.size} (#{laws.count(&:enforced?)} enforced)"
      0
    end
  end
end
