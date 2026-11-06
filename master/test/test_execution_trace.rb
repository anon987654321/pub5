# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/execution_trace"
require "fileutils"
require "yaml"

class TestExecutionTrace < Minitest::Test
  def test_reread_hashes_every_supplied_file
    Dir.mktmpdir("execution_trace") do |root|
      paths = %w[a.rb b.yml c.txt].map do |name|
        path = File.join(root, name)
        File.write(path, "#{name}\n")
        path
      end
      seen = []

      trace = Master::Fix::ExecutionTrace.new(
        root:,
        files: paths,
        digestor: ->(path) { seen << path; Digest::SHA256.file(path) },
        ruby_checker: ->(_path) {},
      )
      trace.send(:reread, paths, failures = [])
      trace.send(:verify_snapshot, paths, failures)

      assert_empty failures
      assert_equal paths.sort, seen.uniq.sort
      assert_equal paths.size * 2, seen.size
    end
  end

  def test_scope_names_become_repository_relative_git_paths
    trace = Master::Fix::ExecutionTrace.new(root: "/tmp/pub4", scope: %w[master rails openbsd studio], ruby_checker: ->(_path) {})

    assert_equal [], trace.send(:scope_paths)
  end

  def test_single_absolute_scope_becomes_a_repository_relative_git_path
    Dir.mktmpdir("execution-trace-scope") do |root|
      FileUtils.mkdir_p(File.join(root, "rails"))
      trace = Master::Fix::ExecutionTrace.new(root:, scope: [File.join(root, "rails")], ruby_checker: ->(_path) {})

      assert_equal ["rails"], trace.send(:scope_paths)
    end
  end

  def test_nested_scope_paths_preserve_lowercase_s_and_commas
    Dir.mktmpdir("execution-trace-nested-scope") do |root|
      %w[studio/dilla/livesets_midi rails/__shared].each do |path|
        FileUtils.mkdir_p(File.join(root, path))
      end
      trace = Master::Fix::ExecutionTrace.new(
        root:,
        scope: ["studio/dilla/livesets_midi, rails/__shared"],
        ruby_checker: ->(_path) {},
      )

      assert_equal ["studio/dilla/livesets_midi", "rails/__shared"], trace.send(:scope_paths)
    end
  end

  def test_full_tree_scope_does_not_swallow_an_extra_token
    Dir.mktmpdir("execution-trace-extra-scope") do |root|
      %w[master rails openbsd studio].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
      trace = Master::Fix::ExecutionTrace.new(
        root:,
        scope: ["master rails openbsd studio,missing"],
        ruby_checker: ->(_path) {},
      )

      error = assert_raises(ArgumentError) { trace.send(:scope_paths) }
      assert_match(/scope does not exist/, error.message)
    end
  end

  def test_empty_explicit_scope_inventory_is_a_failure
    Dir.mktmpdir("execution-trace-empty-scope") do |root|
      FileUtils.mkdir_p(File.join(root, "rails/empty"))
      File.write(File.join(root, "outside.txt"), "outside scope\n")
      system("git", "-C", root, "init", "-q", "--initial-branch=main")

      trace = Master::Fix::ExecutionTrace.new(
        root:,
        scope: ["rails/empty"],
        ruby_checker: ->(_path) {},
      )
      result = trace.run

      refute result.clean?
      assert result.failures.any? { |failure| failure.include?("scope contains no inventoried files") },
             result.failures.inspect
    end
  end

  def test_missing_boot_surface_and_configuration_is_a_failure
    Dir.mktmpdir("execution_trace") do |root|
      trace = Master::Fix::ExecutionTrace.new(root:, files: [], ruby_checker: ->(_path) {})
      result = trace.run

      refute result.clean?
      assert result.failures.any? { |failure| failure.include?("master/bin/master: missing") }
      assert result.failures.any? { |failure| failure.include?("master/data/laws.yml: missing") }
    end
  end

  def test_live_graph_reports_missing_dependency_methods
    trace = Master::Fix::ExecutionTrace.new(
      root: Master::ROOT,
      files: [],
      dependencies: { scanner: Object.new, fix_loop: nil, deliberation: Object.new, bus: Object.new },
    )

    failures = []
    trace.send(:verify_live_graph, failures)

    assert_includes failures, "live_graph: fix_loop missing"
    assert failures.any? { |failure| failure.include?("scanner missing #scan") }
  end

  def test_extracted_fix_and_routing_files_are_in_the_boot_surface
    %w[
      master/lib/cli/routing/model_router.rb
      master/lib/cli/routing/model_router/route_policy.rb
      master/lib/cli/routing/model_router/selection.rb
      master/lib/io/lane_state.rb
      master/lib/fix/outcome_policy.rb
      master/lib/fix/fix_loop/completion.rb
      master/lib/fix/fix_loop/lifecycle.rb
      master/lib/fix/fix_loop/pass_execution.rb
    ].each do |path|
      assert_includes Master::Fix::ExecutionTrace::BOOT_CHAIN, path
    end
  end

  def test_canonical_boot_configuration_does_not_depend_on_workflow_yml
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG.keys, "master/data/workflow.yml"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG.keys, "master/data/budgets.yml"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["master/data/laws.yml"], "transformation_policy"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["master/data/laws.yml"], "ROBUSTNESS"
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["master/data/laws.yml"], "zsh"
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["master/data/laws.yml"], "preserve_user_intent"
  end
  def test_wrapped_ruby_is_checked_after_the_safe_wrapper_repair
    Dir.mktmpdir("execution_trace_wrapper") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "<sub># frozen_string_literal: true\nVALUE = 1\n</sub>\n")

      result = Master::Fix::ExecutionTrace.new(root:, files: [path]).run

      refute result.failures.any? { |failure| failure.include?("syntax failed") }, result.failures.inspect
    end
  end

  def test_wrapped_ruby_is_checked_after_transport_unwrap
    Dir.mktmpdir("execution_trace_wrapper_fallback") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "<sub># frozen_string_literal: true\nVALUE = 1\n</sub>\n")

      result = Master::Fix::ExecutionTrace.new(
        root:,
        files: [path],
        ruby_checker: ->(candidate) { RubyVM::InstructionSequence.compile_file(candidate) },
      ).run

      refute result.failures.any? { |failure| failure.include?("syntax failed") }, result.failures.inspect
    end
  end

  def test_inline_transport_wrapper_is_unwrapped
    Dir.mktmpdir("execution_trace_inline_wrapper") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "VALUE = 1\n</sub>\n")

      result = Master::Fix::ExecutionTrace.new(
        root:,
        files: [path],
        ruby_checker: ->(candidate) { RubyVM::InstructionSequence.compile_file(candidate) },
      ).run

      refute result.failures.any? { |failure| failure.include?("syntax failed") }, result.failures.inspect
    end
  end

  def test_preflight_does_not_allow_ast_fixer_to_mask_syntax_damage
    Dir.mktmpdir("execution_trace_no_fix") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "def broken(\n  true\nend\n")

      candidate = Master::Fix::Scan::AstFixer::Result.new(
        path:,
        changed: true,
        transforms: [:repair],
        content: "def repaired; true; end\n",
      )

      Master::Fix::Scan::AstFixer.stub(:propose, candidate) do
        result = Master::Fix::ExecutionTrace.new(
          root:,
          files: [path],
          ruby_checker: ->(candidate_path) { RubyVM::InstructionSequence.compile_file(candidate_path) },
        ).run

        assert result.failures.any? { |failure| failure.include?("syntax failed") },
               result.failures.inspect
      end
    end
  end

end
