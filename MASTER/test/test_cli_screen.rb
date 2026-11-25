# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"
require_relative "../lib/cli/screen"

# bin/master -S/-ls/-r/-k over a fake tmux that prints canned sessions.
class CliScreenTest < Minitest::Test
  Screen = Master::CLI::Screen

  def setup
    @dir = Dir.mktmpdir("screen")
    @out = StringIO.new
    @execs = []
  end

  def teardown = FileUtils.rm_rf(@dir)

  def fake_tmux(sessions)
    path = File.join(@dir, "tmux")
    rows = File.join(@dir, "rows")

    File.write(rows, sessions.map { |name, attached| "#{name}\t#{attached ? 1 : 0}\t1764100000\truby\n" }.join)
    File.write(path, <<~SH)
      #!/bin/sh
      case "$3" in
        list-sessions) [ -s "#{rows}" ] || exit 1; cat "#{rows}" ;;
        kill-session) [ "$5" = "digest" ] ;;
      esac
    SH
    File.chmod(0o755, path)
    path
  end

  def run_screen(argv, sessions, input: "")
    exec = lambda do |*args|
      @execs << args
      0
    end
    host = Screen::Host.new(tmux: fake_tmux(sessions), input: StringIO.new(input), out: @out, exec:)
    Screen.new(master: "/repo/MASTER/bin/master", root: "/repo/MASTER", host:).run(argv)
  end

  def test_list_names_each_session_and_its_state
    assert_equal 0, run_screen(%w[-ls], [["master", true], ["digest", false]])
    assert_match(/screen0: 2 sessions/, @out.string)
    assert_match(/1 master \(attached, since .*, running ruby\)/, @out.string)
    assert_match(/2 digest \(detached/, @out.string)
  end

  def test_start_creates_a_session_running_master_or_attaches_an_existing_one
    run_screen(%w[-S fix/run], [])
    env, *argv = @execs.last
    assert_equal({ "TMUX" => nil }, env)
    assert_equal ["-L", "master", "new-session", "-s", "fix-run", "-c", "/repo/MASTER", "/repo/MASTER/bin/master"],
                 argv.drop(1)

    run_screen(%w[-S digest], [["digest", false]])
    assert_equal %w[-L master attach-session -t digest], @execs.last.drop(2)
  end

  def test_resume_picks_from_several_by_number_and_refuses_an_unknown_name
    run_screen(%w[-r], [["master", true], ["digest", false]], input: "2\n")
    assert_equal %w[-L master attach-session -t digest], @execs.last.drop(2)
    assert_match(/resume which\?/, @out.string)

    @execs.clear
    assert_equal 1, run_screen(%w[-r nope], [["master", false]])
    assert_empty @execs
    assert_equal 1, run_screen(%w[-r], [])
  end

  def test_resume_with_one_session_attaches_it_directly
    run_screen(%w[-r], [["only", false]])
    assert_equal %w[-L master attach-session -t only], @execs.last.drop(2)
  end

  def test_kill_reports_the_outcome
    assert_equal 0, run_screen(%w[-k digest], [["digest", false]])
    assert_equal 1, run_screen(%w[-k other], [["digest", false]])
    assert_match(/ended digest/, @out.string)
  end
end
