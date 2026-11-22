# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"

class TestScriptDispatch < Minitest::Test
  def test_finds_master_tool_when_operating_from_workspace_root
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "repo_inventory")

    assert_equal File.join(Master::ROOT, "tools", "repo", "repo_inventory.rb"), path
  end

  def test_uses_workspace_as_working_directory_for_fallback_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "repo_inventory")

    assert_equal workspace, Master::Io::ScriptDispatch.working_directory(workspace, script)
  end

  def test_finds_media_tool_under_studio
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "replicate")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "replicate", "client.rb"), path
    assert File.file?(path)
  end

  def test_uses_own_directory_as_working_directory_for_studio_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "replicate")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "replicate"), Master::Io::ScriptDispatch.working_directory(workspace, script)
  end

  def test_lora_uses_the_canonical_studio_photograph_entrypoint
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "lora")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "photograph.rb"), path
    assert File.file?(path)
  end

  # b5acc93bcf deleted postpro by accident on 2026-11-01; the 2026-11-03
  # restore dispatches it through the default <tool>/<tool>.rb probe.
  def test_finds_postpro_under_studio
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "postpro")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "postpro", "postpro.rb"), path
    assert File.file?(path)
  end

  def test_finds_dilla_engine_under_studio
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "dilla")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "dilla", "dilla.rb"), path
    assert File.file?(path)
  end

  def test_reports_signal_termination_instead_of_an_empty_exit_status
    Dir.mktmpdir("master-tool-signal") do |root|
      tool_dir = File.join(root, "tools")
      FileUtils.mkdir_p(tool_dir)
      File.write(File.join(tool_dir, "probe.rb"), "Process.kill(\"TERM\", Process.pid)\n")

      result = Master::Io::ScriptDispatch.run(root:, tool: "probe")

      refute result.ok?
      assert_match(/terminated by signal TERM/, result.message)
      refute_match(/exit=$/, result.message)
    end
  end

  # ScriptDispatch.call speaks each STUDIO tool's JSON API over the subprocess
  # boundary. These use a stub tool under a temp STUDIO root so the dispatch,
  # the stdin request and the response parse are proved without a provider.
  def with_stub_studio(tool, body)
    Dir.mktmpdir("master-studio-api") do |root|
      dir = File.join(root, "STUDIO", tool)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "#{tool}.rb"), body)
      yield root
    end
  end

  def test_call_returns_the_result_hash_from_an_ok_response
    with_stub_studio("probe", <<~'RUBY') do |root|
      require "json"
      request = JSON.parse($stdin.read)
      puts JSON.generate("ok" => true, "result" => { "action" => request["action"], "word" => request["word"] })
    RUBY
      result = Master::Io::ScriptDispatch.call(root:, tool: "probe", action: "echo", params: { "word" => "hei" })

      assert result.ok?, -> { result.message.to_s }
      assert_equal({ "action" => "echo", "word" => "hei" }, result.value!)
    end
  end

  def test_call_turns_a_non_ok_response_into_an_error
    with_stub_studio("probe", <<~'RUBY') do |root|
      require "json"
      puts JSON.generate("ok" => false, "error" => "nope")
    RUBY
      result = Master::Io::ScriptDispatch.call(root:, tool: "probe", action: "boom")

      refute result.ok?
      assert_match(/probe: nope/, result.message)
    end
  end

  def test_call_refuses_a_tool_with_no_api_entrypoint
    result = Master::Io::ScriptDispatch.call(root: Dir.pwd, tool: "nosuch", action: "x")

    refute result.ok?
    assert_match(/missing API entrypoint/, result.message)
  end

  def test_call_turns_unparseable_output_into_an_error
    with_stub_studio("probe", "puts 'not json'\n") do |root|
      result = Master::Io::ScriptDispatch.call(root:, tool: "probe", action: "x")

      refute result.ok?
      assert_match(/unparseable API response/, result.message)
    end
  end

  def test_call_reaches_the_real_lora_api
    result = Master::Io::ScriptDispatch.call(tool: "lora", action: "subjects")

    assert result.ok?, -> { result.message.to_s }
    assert_includes result.value!, "ragnhild"
  end

  def test_tool_child_inherits_master_bundle_environment
    Dir.mktmpdir("master-tool-dispatch") do |root|
      tool_dir = File.join(root, "tools", "probe")
      FileUtils.mkdir_p(tool_dir)
      script = File.join(tool_dir, "probe.rb")
      File.write(script, <<~'RUBY')
        puts [ENV["BUNDLE_GEMFILE"], ENV["BUNDLE_PATH"], ENV["GEM_HOME"], ENV["RUBYOPT"]].map(&:inspect).join(" ")
      RUBY

      # The runner's own BUNDLER_SETUP and BUNDLE_LOCKFILE would pair its lockfile with the fake Gemfile.
      runtime = %w[GEM_HOME GEM_PATH RUBYOPT RUBYLIB]
      previous = ENV.to_h.select { |key, _value| key.start_with?("BUNDLE") || runtime.include?(key) }
      begin
        previous.each_key { |key| ENV.delete(key) }

        File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
        ENV["BUNDLE_GEMFILE"] = File.join(root, "Gemfile")
        ENV["BUNDLE_PATH"] = File.join(root, "bundle")
        ENV["GEM_HOME"] = File.join(root, "gems")
        ENV["GEM_PATH"] = File.join(root, "gems")
        ENV["RUBYOPT"] = ""

        result = Master::Io::ScriptDispatch.run(root:, tool: "probe")

        assert result.ok?, -> { result.message.to_s }
        assert_equal %Q{"#{ENV["BUNDLE_GEMFILE"]}" "#{ENV["BUNDLE_PATH"]}" "#{ENV["GEM_HOME"]}" ""}, result.value!
      ensure
        ENV.keys.grep(/\ABUNDLE/).each { |key| ENV.delete(key) }
        %w[GEM_HOME GEM_PATH RUBYOPT RUBYLIB].each { |key| ENV.delete(key) }
        previous.each { |key, value| ENV[key] = value }
      end
    end
  end
end
