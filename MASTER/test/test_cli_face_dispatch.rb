# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face/transcriber"
require_relative "../lib/cli/face/ear"

class TestCliFaceDispatch < Minitest::Test
  def test_master_boot_loads_the_master_operator_mode
    assert defined?(Master::Operator::Mode), "interactive fold routing needs Master::Operator::Mode"
  end

  def test_fix_registry_loads_the_foreign_check_chain_before_dispatch
    require_relative "../lib/cli/command_registry/review"

    assert defined?(::Operator::CheckChain), "fix registry must load top-level Operator::CheckChain"
  end

  def test_run_input_starts_a_new_ground_truth_turn_before_dispatch
    session = Master::CLI::Session.allocate
    truth = Master::Ground::Truth.new
    session.instance_variable_set(:@refs, Struct.new(:ground_truth).new(truth))
    session.instance_variable_set(:@turn_queue_mutex, Mutex.new)
    session.define_singleton_method(:turn_cancel_requested?) { false }
    session.define_singleton_method(:check_budget_blocks) { |*| nil }
    session.define_singleton_method(:init_turn_state) { |_input| [false, { streamed: false }, []] }
    session.define_singleton_method(:dispatch_turn) do |*_args|
      Master::Result.ok(truth.current_turn_id)
    end
    session.define_singleton_method(:print_thinking_indicator) {}
    session.define_singleton_method(:stop_thinking_indicator) {}
    session.define_singleton_method(:close_unit_console) {}
    session.define_singleton_method(:print_bridge_footer) { |*| nil }
    session.define_singleton_method(:display_result) { |*| nil }

    result = session.run_input("hello")

    assert result.ok?
    assert_equal 1, result.value!
  end

  def test_registered_slash_command_starts_a_new_ground_truth_turn
    session = Master::CLI::Session.allocate
    truth = Master::Ground::Truth.new
    session.instance_variable_set(:@refs, Struct.new(:ground_truth).new(truth))
    session.instance_variable_set(:@container, {
      commands: {
        "probe" => ->(args:) {
          Master::Result.ok("turn=#{truth.current_turn_id}")
        },
      },
    })
    session.define_singleton_method(:print_terminal_output) { |*| nil }

    result = session.send(:dispatch_registered_slash_command, "/probe")

    assert result.ok?
    assert_equal "turn=1", result.value!
  end

  def test_known_slash_commands_bypass_the_llm_turn
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: {
        "play" => Master::CLI::CommandRegistry::Command.new { |ctx| "dilla0: #{ctx.fetch(:args)}" },
      },
    })
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))
    out, = capture_io { session.send(:dispatch_core_slash_command, "/play flying lotus") }
    assert_includes out, "dilla0: flying lotus"
  end

  def test_unknown_slash_command_still_reaches_the_sentence_router
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, { commands: {} })
    assert_equal :unhandled, session.send(:dispatch_core_slash_command, "/not-a-command")
  end

  def test_terminal_agent_turn_runs_the_turn_in_process
    session = Master::CLI::Session.allocate
    session.define_singleton_method(:host_refusal_for) { |_line| nil }
    calls = []
    session.define_singleton_method(:run_input) do |line|
      calls << line
      :result
    end

    assert_equal :result, session.send(:run_agent_turn, "hello")
    assert_equal ["hello"], calls
  end

  def test_undo_uses_the_registered_command_instead_of_the_model_turn
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: {
        "undo" => Master::CLI::CommandRegistry::Command.new { "reverted: note.txt" },
      },
    })
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))
    out, = capture_io { session.send(:dispatch_core_slash_command, "/undo") }

    assert_includes out, "reverted: note.txt"
  end

  def test_repeat_last_sends_the_last_repeatable_input_again
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@last_repeatable_input, "repeat me")
    calls = []
    session.define_singleton_method(:run_input) do |input|
      calls << input
      :repeated
    end

    assert_equal :repeated, session.send(:repeat_last)
    assert_equal ["repeat me"], calls
  end

  def test_direct_shell_returns_the_result_to_the_terminal
    session = Master::CLI::Session.allocate
    shell = Object.new
    shell.define_singleton_method(:call) { |command:| Master::Result.ok("shell output") }
    session.define_singleton_method(:bang_shell) { shell }
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))

    out, = capture_io { session.send(:run_direct_shell, "echo hello") }

    assert_includes out, "shell output"
    assert_equal 0, session.instance_variable_get(:@exit_code)
  end

  def test_cd_changes_the_persistent_repl_directory_inside_the_checkout
    original = Dir.pwd
    workspace = File.realpath(Master.repo_root)
    Dir.chdir(File.join(workspace, "MASTER"))
    session = Master::CLI::Session.allocate
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))
    session.define_singleton_method(:terminal_puts) { |_text, **| }

    result = session.send(:run_direct_shell, "cd ..")

    assert_equal :changed, result
    assert_equal workspace, Dir.pwd
    assert_nil session.instance_variable_get(:@bang_shell)
  ensure
    Dir.chdir(original) if original
  end

  def test_cd_refuses_to_leave_the_checkout
    original = Dir.pwd
    workspace = File.realpath(Master.repo_root)
    Dir.chdir(workspace)
    session = Master::CLI::Session.allocate
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))
    session.define_singleton_method(:terminal_puts) { |_text, **| }

    result = session.send(:run_direct_shell, "cd /tmp")

    assert_equal :failed, result
    assert_equal workspace, Dir.pwd
  ensure
    Dir.chdir(original) if original
  end

  def test_help_returns_its_text_to_the_terminal
    session = Master::CLI::Session.allocate
    printed = []
    session.define_singleton_method(:print_terminal_output) { |text, **| printed << text }

    result = Master::CLI::CommandRegistry.stub(:help_text, "status help") do
      session.send(:run_help, "status")
    end

    assert result.ok?
    assert_equal "status help", result.value!
    assert_equal ["status help"], printed
  end

  def test_clear_dispatches_the_deterministic_registered_command
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: {
        "clear" => Master::CLI::CommandRegistry::Command.new { "context cleared" },
      },
    })
    renderer = Object.new
    def renderer.render(text, **); text; end
    session.instance_variable_set(:@refs, Struct.new(:renderer).new(renderer))

    out, = capture_io { session.send(:dispatch_core_slash_command, "/clear") }

    assert_includes out, "context cleared"
  end

  def test_registered_command_failure_is_returned_as_a_visible_error
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@container, {
      commands: { "broken" => ->(args:) { raise IOError, "command output unavailable" } },
    })
    session.define_singleton_method(:print_terminal_output) { |*| nil }

    result = session.send(:dispatch_registered_slash_command, "/broken")

    # A failed command answers nil; the terminal already printed the error and
    # the exit code carries the failure out of pipe mode.
    assert_nil result
    assert_equal 2, session.instance_variable_get(:@exit_code)
  end

  def test_listen_command_sends_one_consented_transcript_through_the_existing_session
    ear = Object.new
    ear.define_singleton_method(:missing) { nil }
    ear.define_singleton_method(:listen) do |stop:, on_partial:|
      raise "unexpected stop" if stop.call
      raise "unexpected interim callback" unless on_partial.nil?

      "voice transcript"
    end
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:root).new(Master::REPO_ROOT))
    output = []
    submitted = []
    session.define_singleton_method(:terminal_puts) { |line| output << line }
    session.define_singleton_method(:run_agent_turn) { |text| submitted << text; :submitted }

    result = Master::CLI::Face::Ear.stub(:new, ear) do
      session.send(:dispatch_core_slash_command, "/listen")
    end

    assert_equal :submitted, result
    assert_equal ["voice transcript"], submitted
    assert_equal ["mic0: listening"], output
  end

  def test_listen_does_not_open_the_microphone_without_both_local_grants
    ear = Object.new
    ear.define_singleton_method(:missing) { "mic0: voice input is off by default" }
    ear.define_singleton_method(:listen) { |**| flunk("permission-denied microphone was opened") }
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:root).new(Master::REPO_ROOT))
    output = []
    session.define_singleton_method(:terminal_puts) { |line| output << line }

    Master::CLI::Face::Ear.stub(:new, ear) { session.send(:dispatch_core_slash_command, "/listen") }

    assert_equal ["mic0: voice input is off by default"], output
  end


  def test_general_help_discloses_the_zsh_timeout
    session = Master::CLI::Session.allocate
    printed = []
    session.define_singleton_method(:print_terminal_output) { |text, **| printed << text }
    Master::CLI::CommandRegistry.stub(:help_summary, "summary") do
      session.send(:run_help)
    end

    assert_includes printed.fetch(0), "30-second timeout"
    assert_includes printed.fetch(0), "Longer commands may be terminated"
  end

end
