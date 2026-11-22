# frozen_string_literal: true

require_relative "test_helper"

class TestRubySelectorEnvironment < Minitest::Test
  def test_malloc_stack_logging_is_removed_before_any_ruby_probe
    source = File.read(File.join(Master::ROOT, "bin", "ruby"), encoding: "UTF-8")
    cleanup = source.index("MallocStackLogging*")
    first_probe = source.index('version=$("$ruby" -e')

    refute_nil cleanup, "the shell launcher must clear inherited allocator diagnostics"
    refute_nil first_probe, "the launcher must retain its candidate version probe"
    assert_operator cleanup, :<, first_probe,
                    "cleanup must run before the first Ruby process starts"

    # The loop's own variable name is its business; that the matched branch
    # unsets that same variable is the invariant. Read it from the source
    # instead of pinning the literal `$name` the script no longer uses.
    loop_variable = source[/for (\w+) in \$\{\(k\)parameters\}/, 1]
    refute_nil loop_variable, "the launcher must walk the inherited shell parameters"
    assert_match(/MallocStackLogging\*\)\s*unset "\$#{loop_variable}"/, source,
                 "the MallocStackLogging branch must unset the parameter it matched")
  end
end
