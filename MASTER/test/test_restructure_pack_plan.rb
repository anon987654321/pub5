# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/fix/restructure/pack_plan"

# RADICAL_STRUCTURE's pack mode. Every case runs in a throwaway tree; the
# planner only renders Restructure plan text and never touches the checkout.
class TestRestructurePackPlan < Minitest::Test
  PackPlan = Master::Fix::Restructure::PackPlan

  def setup
    @root = Dir.mktmpdir("pack_plan_test")
    @lib = File.join(@root, "lib")
    FileUtils.mkdir_p(File.join(@lib, "face"))
    FileUtils.mkdir_p(File.join(@lib, "voice", "boot_sound"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  PARENT = <<~RUBY
    # frozen_string_literal: true

    module Master
      module Face
        def self.base = "base"
      end
    end
  RUBY

  CHILD = <<~RUBY
    # frozen_string_literal: true

    require_relative "../face"

    module Master
      module Face
        module Swarm
          def self.field = "particles"
        end
      end
    end
  RUBY

  VOICE_PARENT = <<~RUBY
    # frozen_string_literal: true

    module Master
      module Voice
        module BootSound
          VOICES = 3
        end
      end
    end
  RUBY

  VOICE_CHILD = <<~RUBY
    # frozen_string_literal: true

    require_relative "../../trace/dmesg"

    module Master
      module Voice
        module BootSound
          module Dsp
            STAGES = 4
          end
        end
      end
    end
  RUBY

  def write(path, body)
    File.write(File.join(@lib, path), body)
  end

  # Writes the face pair and returns the packed parent body the planner
  # renders for it.
  def packed_face_body
    write("face.rb", PARENT)
    write("face/swarm.rb", CHILD)
    PackPlan.candidates(@lib).fetch(0).packed_body
  end

  def trailing_ends(body)
    body.rstrip.lines.reverse.take_while { |line| line.strip == "end" }.size
  end

  def assert_valid_ruby(body)
    RubyVM::AbstractSyntaxTree.parse(body)
  end

  def test_a_single_file_directory_with_a_parent_file_is_a_candidate
    write("face.rb", PARENT)
    write("face/swarm.rb", CHILD)

    candidates = PackPlan.candidates(@lib)

    assert_equal 1, candidates.size
    assert_equal "swarm.rb", candidates.fetch(0).file.basename.to_s
    assert_equal "face.rb", candidates.fetch(0).parent_file.basename.to_s
  end

  def test_the_packed_parent_defines_the_child_constant_inside_its_chain
    body = packed_face_body

    assert_valid_ruby(body)
    assert_equal 3, trailing_ends(body), "the appended Swarm end plus the parent's own two ends"
    assert_includes body, %(def self.base = "base")
    assert_includes body, %(def self.field = "particles")
    assert_includes body, "module Swarm", "the packed constant keeps its name"
    assert_operator body.index("def self.base"), :<, body.index("def self.field")
    refute_includes body, "require_relative"
  end

  def test_the_plan_names_the_merge_operation_from_the_repository_root
    packed_face_body

    plan = PackPlan.plan_text(plan_root: @root, scan_root: @lib)

    assert plan
    assert_includes plan, "SUMMARY: Pack 1 single-file directory into its parent namespace file"
    assert_includes plan, "OPERATIONS: merge"
    assert_includes plan, "=== WRITE lib/face.rb"
    assert_includes plan, "=== DELETE lib/face/swarm.rb"
  end

  def test_a_child_chain_that_does_not_extend_the_parent_chain_is_skipped
    write("face.rb", PARENT)
    write("face/swarm.rb", CHILD.sub("module Master", "module Elsewhere"))

    assert_empty PackPlan.candidates(@lib)
  end

  def test_a_parent_that_does_not_close_its_chain_at_the_end_is_skipped
    write("face.rb", "#{PARENT}\n# a postscript after the chain\n")
    write("face/swarm.rb", CHILD)

    assert_empty PackPlan.candidates(@lib)
  end

  def test_a_child_still_referenced_elsewhere_is_skipped
    write("face.rb", PARENT)
    write("face/swarm.rb", CHILD)
    write("other.rb", "# frozen_string_literal: true\n\nrequire_relative \"face/swarm\"\n")

    assert_empty PackPlan.candidates(@lib)
  end

  def test_a_directory_holding_more_than_the_one_file_is_not_a_candidate
    write("face.rb", PARENT)
    write("face/swarm.rb", CHILD)
    write("face/notes.md", "notes\n")

    assert_empty PackPlan.candidates(@lib)
  end

  def test_a_deeper_child_loses_one_level_from_its_own_relative_requires
    write("voice/boot_sound.rb", VOICE_PARENT)
    write("voice/boot_sound/dsp.rb", VOICE_CHILD)

    body = PackPlan.candidates(@lib).fetch(0).packed_body

    assert_valid_ruby(body)
    assert_includes body, 'require_relative "../trace/dmesg"'
    assert_includes body, "STAGES = 4"
    assert_equal 4, trailing_ends(body), "the appended Dsp end plus the parent's own three ends"
  end
end
