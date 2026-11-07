# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../laws/engine"

# Native pub5 proof surface for imported pub4 structural Laws. Law.load!
# evaluates each imported Law's own bad/good fixtures before these examples
# run; each test binds that proof to one Law and its pub5-owned test file.
class ImportedPub4ProofsTest < Minitest::Test
  PROOF_IDS = %i[
    RUNTIME_DOCS_YAML
    LEARNED_SMELLS
    FILE_SPRAWL
    PATH_PURPOSE
    PARAMETERIZED_SLUG
    TYPE_IN_NAME
    NUMBERED_NAME
    FILE_SEQUENCE_NAME
    FILE_VAGUE_NAME
    FILE_LAYOUT
    CYCLOMATIC_COMPLEXITY
    PATTERN_EXTRACTION
    DATA_CLASS
    LIB_ROOT_DISCIPLINE
    SMALL_FILES
    SMALL_FUNCTIONS
    NO_GOD_CLASS
    NESTING_DEPTH
    CQS
    OPEN_CLOSED
    LISKOV
    DEPENDENCY_INVERSION
    INTERFACE_SEGREGATION
    MIDDLE_MAN
    CONFIG_HIERARCHY
    CODE_HIERARCHY
    LONG_PARAMETER_LIST
    PRIMITIVE_OBSESSION
    BOOLEAN_TRAP
    DATA_CLUMPS
    COUPLER_SMELLS
    FEATURE_ENVY
    LAZY_CLASS
  ].freeze

  def self.proof_laws
    @proof_laws ||= Law.load!.to_h { |law| [law.id, law] }
  end

  PROOF_IDS.each do |id|
    define_method("test_#{id.to_s.downcase}_has_a_pub5_proof") do
      law = self.class.proof_laws.fetch(id)
      assert_predicate law, :imported?
      assert_nil law.broken
      assert_equal "test/laws/imported_pub4_proofs_test.rb", law[:proved_by]
    end
  end
end
