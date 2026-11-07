# frozen_string_literal: true

module Law
  # The Law.define DSL. Its words are pub4's Law::Builder words, so a pub4
  # Law body imports unchanged; only policy words (severity, lifecycle, ...)
  # are refused here because policy lives in registry/laws.yml.
  class Builder
    VALUE_WORDS = %i[source scope absent ask practice fix bad good reads_comments transform
                     reads_beyond_file proved_by example_path].freeze

    VALUE_WORDS.each { |word| define_method(word) { |value| @h[word] = value } }

    def initialize(id)
      @h = { id:, scope: :line, tags: [], languages: [], surfaces: [], adapters: [], reads_comments: false }
    end

    def detect(&block) = @h[:detect] = block
    def check(&block) = @h[:check] = block
    def detector(klass) = @h[:detector] = klass
    def pattern(source) = @h[:detect] = Regexp.union(Array(source).map { |s| s.is_a?(Regexp) ? s : Regexp.new(s) }).method(:match?)
    def tags(*names) = @h[:tags] = names.flatten.map(&:to_sym)
    def languages(*names) = @h[:languages] = names.flatten.map(&:to_s)
    def measures(*surfaces) = @h[:surfaces] = surfaces.flatten.map(&:to_sym)
    def surfaces(*surfaces) = measures(*surfaces)

    def path(subject)
      refuse "path must be a String or a Regexp" unless subject.is_a?(String) || subject.is_a?(Regexp)
      @h[:path] = subject
    end

    # `adapter(:file_names, bad: [...], good: [...]) { |paths| ... }` reads the
    # tree; `adapter(:structured_data, languages: %w[yaml], bad:, good:) { |text, file| }`
    # reads one file.
    def adapter(*surfaces, bad:, good:, languages: [], example_path: nil, &check)
      @h[:adapters] += [Adapter.new(surfaces: surfaces.flatten.map(&:to_sym), languages: languages.map(&:to_s),
                                    check:, bad:, good:, example_path:)]
    end

    POLICY_WORDS.each do |word|
      define_method(word) { |*| refuse "#{word} is policy; it lives in registry/laws.yml" }
    end

    # The row is the Law's registry policy; a Law under laws/pub4/ reads it for
    # pub4's severity, catalogue languages and path_exclude.
    def build(row = {})
      detectors = %i[detect check detector].count { |k| @h[k] }
      refuse "detect, check and detector are three detectors; keep one" if detectors > 1
      if detectors.zero? && @h[:adapters].empty? && !@h[:ask] && !@h[:practice]
        refuse "needs detect, check, detector, adapter, ask or practice"
      end
      # A deterministic Law proves its fixtures or its named test at load; a
      # semantic Law's ask is its review rubric and proves through the census
      # (its evidence review runs live, not at load), so only the detector
      # half owes a worked pair. What prove! never checks, build does not
      # refuse.
      if detectors.positive? && !@h[:proved_by] && !(@h.key?(:bad) && @h.key?(:good))
        refuse "needs bad and good fixtures, or proved_by"
      end
      Definition.new(@h, row)
    end

    private

    def refuse(reason) = raise(Invalid, "#{@h[:id]}: #{reason}")
  end
end
