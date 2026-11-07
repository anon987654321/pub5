# frozen_string_literal: true

# The loader contract pub4's acceptance instrument reads a target through
# (MASTER/tools/law_fixture_runner.rb): "require laws/definition", then
# Law.load_all over the target's law dir, then Law.definitions, then
# law.send(:scan_main, fixture, file). pub5's one engine lives in
# laws/engine.rb, so this file is the adapter between the two spellings of
# the same contract, not a second engine: load_all loads every law file
# exactly the way bin/check's law stage does (tolerating only rows the
# index marks broken, so unknown failures surface as runner diffs), and
# Definition answers the pub4 engine's method names, which the imported
# detector hook (laws/pub4/master/lib/review/scan/detector.rb) walks when
# ::Law.definitions exists - it self-disables without this file, so these
# names reach nothing but the instrument.
require_relative "engine"

module Law
  class << self
    def load_all(dir)
      dir = File.expand_path(dir)
      @laws.clear
      load_files(dir, Core::Registry.load(:laws).fetch("laws"))
      nil
    end

    def definitions = @laws
  end

  # pub4's engine named law members as methods (MASTER/law/definition.rb
  # MEMBERS); pub5 keeps them in options and policy. The runner and the
  # imported detector hook read them the pub4 way: law_definition finds the
  # definition whose detector is the class, then bind takes id, ask, fix,
  # severity, tags, autofix, mode and languages from it.
  class Definition
    def scan_main(text, file)
      return @pub4.send(:scan_main, text, Pub4.name(file)) if @pub4

      main_hits(text, file)
    end

    def detector = self[:detector]
    def ask = self[:ask]
    def fix = self[:fix]
    def languages = Array(self[:languages])
    def tags = Array(self[:tags])

    def autofix
      value = self[:autofix] || @policy["autofix"]
      value ? value.to_sym : :review
    end

    def mode
      (self[:mode] || @policy["mode"] || "violation").to_sym
    end
  end
end
