# frozen_string_literal: true

require_relative "test_helper"

class TestCLITerminalOutput < Minitest::Test
  Renderer = Struct.new(:calls) do
    def render(text, mode:)
      calls << [text, mode]
      "#{mode}:#{text}"
    end
  end

  def session
    Master::CLI::Session.allocate.tap do |cli|
      cli.instance_variable_set(:@refs, Struct.new(:renderer, :bus).new(Renderer.new([]), nil))
    end
  end

  def test_long_output_is_pageable_only_on_a_terminal
    output = "row\n" * 30

    $stdout.stub(:tty?, false) do
      refute session.send(:pageable_output?, output)
    end

    saved = ENV["MASTER_PAGER"]
    ENV["MASTER_PAGER"] = "0"
    $stdout.stub(:tty?, true) do
      TTY::Screen.stub(:height, 24) do
        refute session.send(:pageable_output?, output)
      end
    end

    ENV.delete("MASTER_PAGER")
    $stdout.stub(:tty?, true) do
      TTY::Screen.stub(:height, 24) do
        assert session.send(:pageable_output?, output)
      end
    end
  ensure
    saved.nil? ? ENV.delete("MASTER_PAGER") : ENV["MASTER_PAGER"] = saved
  end

  def test_pager_selection_rejects_shell_fragments
    saved = ENV["MASTER_PAGER"]
    ENV["MASTER_PAGER"] = "less; rm -rf /"

    Master::Trace::Dmesg.stub(:status, ->(*) {}) do
      assert_nil session.send(:terminal_pager_command)
    end
  ensure
    saved.nil? ? ENV.delete("MASTER_PAGER") : ENV["MASTER_PAGER"] = saved
  end

  def test_empty_tab_completion_prioritises_common_commands_and_slash_opens_full_surface
    cli = session
    previous = Reline.completion_proc
    cli.send(:setup_completion)
    completion = Reline.completion_proc

    Reline.stub(:line_buffer, "") do
      expected = Master::CLI::Session::QUICK_COMMAND_COMPLETIONS.map { |command| "#{command} " }
      assert_equal expected, completion.call("")
      assert_includes expected, "/doctor "
      assert_empty Master::CLI::Session::QUICK_COMMAND_COMPLETIONS - Master::CLI::CommandRegistry.slash_commands
      refute_includes expected, "/review "
      refute_includes expected, "/critique "
      refute_includes expected, "/deploy "
    end
    Reline.stub(:line_buffer, "/") do
      expected = Master::CLI::CommandRegistry.slash_commands.reject { |command| %w[/exit /quit].include?(command) }
      assert_equal expected, completion.call("")
    end
  ensure
    Reline.completion_proc = previous
  end

  def test_first_run_hint_uses_one_plain_actionable_dmesg_line
    cli = session
    rows = []
    Master::Trace::Dmesg.stub(:status, ->(unit, message, **_options) { rows << [unit, message] }) do
      $stdin.stub(:tty?, true) do
        $stdout.stub(:tty?, true) { cli.send(:print_quick_start) }
      end
    end

    assert_equal "input0", rows.fetch(0).fetch(0)
    assert_match(/plain language/, rows.fetch(0).fetch(1))
    assert_match(/Tab/, rows.fetch(0).fetch(1))
    assert_match(%r{/help}, rows.fetch(0).fetch(1))
  end

  def test_piped_output_stays_plain_and_does_not_start_a_pager
    text = "row\n" * 30
    stdout, = capture_io do
      session.send(:print_terminal_output, text, mode: :dim)
    end

    # puts adds no newline after text that already ends in one.
    assert_equal "dim:#{text}", stdout
  end

  def test_routine_unit_lines_are_suppressed_until_diagnostic_verbosity_is_requested
    previous_dmesg = ENV["MASTER_DMESG"]
    previous_quiet = ENV["MASTER_CLI_QUIET"]
    ENV["MASTER_DMESG"] = "normal"
    ENV.delete("MASTER_CLI_QUIET")

    refute session.send(:verbose_output?)

    ENV["MASTER_DMESG"] = "verbose"
    assert session.send(:verbose_output?)
  ensure
    previous_dmesg.nil? ? ENV.delete("MASTER_DMESG") : ENV["MASTER_DMESG"] = previous_dmesg
    previous_quiet.nil? ? ENV.delete("MASTER_CLI_QUIET") : ENV["MASTER_CLI_QUIET"] = previous_quiet
  end

  def test_conversational_replies_use_irc_lines_on_a_tty
    cli = session
    cli.instance_variable_set(:@last_input, "hello")

    output = $stdout.stub(:tty?, true) do
      cli.send(:format_irc_reply, "Hello.\n\nHow are you?")
    end

    rows = output.lines(chomp: true)
    assert_match(/\A\[\d{2}:\d{2}\] <master> Hello\.\z/, rows.fetch(0))
    assert_equal "", rows.fetch(1)
    assert_match(/\A\[\d{2}:\d{2}\] <master> How are you\?\z/, rows.fetch(2))
  end

  def test_normal_chat_unwraps_the_accidental_ruby_say_helper
    cli = session
    cli.instance_variable_set(:@last_input, "tell xmas story")
    wrapper = <<~'RUBY'
      STDOUT.sync = true
      def say(line = "")
        STDOUT.puts(line.to_s)
      end
      def safe
        yield
      rescue => e
        nil
      end
      safe do
        say "The house was quiet."
        say
        say "The tree lights were warm."
      end
    RUBY

    assert_equal "The house was quiet.\n\nThe tree lights were warm.",
                 cli.send(:conversation_output, wrapper)
  end

  def test_ordinary_question_about_a_language_is_still_conversation
    cli = session
    cli.instance_variable_set(:@last_input, "what is Ruby?")
    wrapper = <<~'RUBY'
      STDOUT.sync = true
      def say(line = "")
        STDOUT.puts(line.to_s)
      end
      def safe
        yield
      end
      safe do
        say "Ruby is a programming language."
      end
    RUBY

    assert_equal "Ruby is a programming language.",
                 cli.send(:conversation_output, wrapper)
  end

  def test_explicit_code_request_is_not_unwrapped
    cli = session
    cli.instance_variable_set(:@last_input, "show me Ruby code")
    wrapper = <<~'RUBY'
      STDOUT.sync = true
      def say(line = "")
        STDOUT.puts(line.to_s)
      end
      def safe
        yield
      end
      safe do
        say "literal"
      end
    RUBY

    assert_equal wrapper, cli.send(:conversation_output, wrapper)
  end

  def test_two_voice_rings_render_as_a_fixed_top_right_overlay
    cli = session
    cli.define_singleton_method(:voice_indicator_state) { [false, false] }

    overlay = TTY::Screen.stub(:width, 80) { cli.send(:voice_indicator_overlay) }

    assert_match(/\A\e7\e\[1;77H/, overlay)
    assert_includes overlay, "○ ○"
    assert_match(/\e8\z/, overlay)
    refute_includes overlay, "\e[s"
    refute_includes overlay, "\e[u"
  end
end
