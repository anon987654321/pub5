# frozen_string_literal: true

require_relative "test_helper"

class TestDmesgDetail < Minitest::Test
  Dmesg = Master::Trace::Dmesg

  def setup
    @env = %w[MASTER_DMESG MASTER_DMESG_DETAIL MASTER_QUIET NO_COLOR].to_h do |key|
      [key, ENV[key]]
    end
    @draft_guard = Dmesg.draft_guard
    ENV.delete("MASTER_DMESG")
    ENV.delete("MASTER_DMESG_DETAIL")
    ENV.delete("MASTER_QUIET")
    ENV.delete("NO_COLOR")
    Dmesg.draft_guard = nil
    Fiber[:master_dmesg_detail_units] = nil
    Dmesg.reload!
  end

  def teardown
    @env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Dmesg.draft_guard = @draft_guard
    Fiber[:master_dmesg_detail_units] = nil
    Dmesg.reload!
  end

  def enable_detail
    ENV["MASTER_DMESG_DETAIL"] = "1"
  end

  def test_detail_is_silent_without_explicit_consent
    output = StringIO.new

    Dmesg.detail("read0", "private source", io: output)

    assert_empty output.string
  end

  def test_detail_preserves_newlines_and_indents_under_its_unit
    enable_detail
    output = StringIO.new

    Dmesg.detail("llm0", "prompt:\nfirst line\nsecond line", io: output)

    assert_equal "  llm0: prompt:\n  llm0: first line\n  llm0: second line\n", output.string
  end

  def test_detail_truncates_a_long_line_at_the_configured_character_limit
    enable_detail
    Dmesg.instance_variable_set(:@cfg, Dmesg.cfg.merge("detail_max_chars" => 12))
    output = StringIO.new

    Dmesg.detail("read0", "x" * 5_000, io: output)

    body = output.string.lines.first.delete_prefix("  read0: ").chomp
    assert_equal 12, body.length
    assert body.end_with?("…")
  end

  def test_detail_reports_omitted_lines_instead_of_implying_they_were_complete
    enable_detail
    Dmesg.instance_variable_set(:@cfg, Dmesg.cfg.merge("detail_max_lines" => 8))
    output = StringIO.new

    Dmesg.detail("read0", (1..50).map { |n| "line #{n}" }.join("\n"), io: output)

    lines = output.string.lines
    assert_equal 9, lines.size
    assert_equal "  read0: … 42 more line(s)\n", lines.last
  end

  def test_detail_uses_the_terminal_write_draft_guard
    enable_detail
    calls = []
    Dmesg.draft_guard = [
      ->(_io) { calls << :begin },
      ->(_io) { calls << :end },
    ]

    Dmesg.detail("write0", "diff", io: StringIO.new)

    assert_equal %i[begin end], calls
  end

  def test_no_color_keeps_detail_plain_even_on_a_terminal
    enable_detail
    ENV["NO_COLOR"] = "1"
    terminal = Class.new(StringIO) { def tty? = true }.new

    Dmesg.detail("fix0", "diff", io: terminal, style: :add)

    refute_match(/\e\[/, terminal.string)
  end

  def test_everything_is_trace_plus_detail
    Dmesg.with_verbosity("everything") do
      assert_equal "everything", Dmesg.verbosity
      assert Dmesg.verbose?
      assert Dmesg.trace?
      assert Dmesg.detail_enabled?
    end
  end

  def test_detail_disables_model_call_burst_rollups
    enable_detail
    Dmesg.with_verbosity("normal") do
      console = Dmesg::Console.new
      lines = 8.times.flat_map do
        console.lines(event: "llm:send", model: "provider/model") +
          console.lines(event: "llm:provider_outcome", model: "provider/model", status: :success, latency_ms: 10)
      end

      assert_equal 16, lines.size
      assert lines.all? { |line| line.start_with?("llm") }
    end
  end

  def test_tool_details_reuse_the_numbered_unit_from_the_event_console
    enable_detail
    console = Dmesg::Console.new
    console.lines(event: "tool:call", tool: "read_file", subject_kind: "path", subject_bytes: 9)
    output = StringIO.new

    Dmesg.detail("read_file", "file content", io: output)

    assert_equal "  read0: file content\n", output.string
  end

  def test_diff_head_contains_hunks_without_temporary_file_headers
    diff = Dmesg.diff_head("before\n", "after\n")

    assert_includes diff, "-before"
    assert_includes diff, "+after"
    refute_includes diff, "unified-diff"
  end
end
