# frozen_string_literal: true

require "json"
require "stringio"
require_relative "../test_helper"
require_relative "../../master/cli/repl"
require_relative "../../master/cli/ask"

# The CLI and REPL contracts from pub4 TODO.md section 5 and the UX matrix of
# section 8.2 (MASTER/data/ux_refinements.yml), one test each, named by row.
# Every turn runs end to end: a stub `claude` that answers in the json result
# shape, through Models::Dispatch, World#exec and the ledger.
class CliTest < Minitest::Test
  include TestHelper

  VERBS = { read: ["log/master/*"], write: ["log/master/*"], exec: %w[claude grok], llm: %w[anthropic] }.freeze
  PIN = { "PUB5_MODEL" => "claude-cli:claude-opus-5-5" }.freeze
  # Answers with the last stdin line, quoting curly marks and a key so the
  # terminal's ASCII and redaction are on the path.
  CLAUDE = <<~RUBY
    said = STDIN.read.lines.last.to_s.strip.delete_prefix("user: ")
    exit 3 if said.include?("crash")
    sleep 30 if said.include?("slow")
    reply = "svar: \\u201C\#{said}\\u201D"
    reply += " key sk-ant-abcdefghijklmnopqrstuv" if said.include?("secret")
    puts JSON.generate("type" => "result", "is_error" => false, "result" => reply,
                       "usage" => { "input_tokens" => 4, "output_tokens" => 2 }, "total_cost_usd" => 0.001)
  RUBY

  def setup
    @dir = Dir.mktmpdir("pub5-cli")
    @root = File.realpath(@dir)
    put(@root, "bin/claude", "#!/usr/bin/env ruby\nrequire \"json\"\n#{CLAUDE}")
    File.chmod(0o755, File.join(@root, "bin/claude"))
    @now = 0.0
  end

  def teardown = FileUtils.remove_entry(@dir)

  def world_for(env) = world(@root, VERBS, env:)

  def dispatch(w, env)
    k = knobs(env)
    catalog = Models::Catalog.new
    lanes = Models::Lanes.new(catalog:, store: Models::Lanes::Store.new(w))
    Models::Dispatch.new(world: w, catalog:, lanes:, router: Models::Router.new(catalog:, lanes:, knobs: k),
                         gate: Models::Gate.new(lanes:, sleeper: ->(_) {}), knobs: k, bin_dir: File.join(@root, "bin"))
  end

  def conversation(env = PIN, w = world_for(env))
    memory = Memory::Store.new(world: w)
    Cli::Conversation.new(world: w, dispatch: dispatch(w, env), memory:,
                          mind: Cognition::Mind.new(store: Cognition::Mind::Store.new(w), memory:))
  end

  # Runs a REPL over lines; returns [stdout, stderr, exit status].
  def repl(lines, context: "pipe", env: PIN, conv: nil)
    out = StringIO.new
    err = StringIO.new
    w = world_for(env)
    r = Cli::Repl.new(world: w, context:, input: StringIO.new(lines.join("\n")), out:, err:,
                      conversation: conv || conversation(env, w), clock: -> { @now += 0.5 })
    code = context == "tty" ? lines.each { |l| r.handle(l) } && 0 : r.call([])
    [out.string, err.string, code]
  end

  def ask(argv, env: PIN, input: "")
    out = StringIO.new
    err = StringIO.new
    w = world_for(env)
    code = Cli::Ask.new(world: w, context: "pipe", input: StringIO.new(input), out:, err:, dispatch: dispatch(w, env)).call(argv)
    [out.string, err.string, code]
  end

  # Drives the tty boot alone: boot_dmesg, not call, so Reline never starts.
  def tty_boot
    out = StringIO.new
    err = StringIO.new
    w = world_for(PIN)
    r = Cli::Repl.new(world: w, context: "tty", input: StringIO.new(""), out:, err:,
                      conversation: conversation(PIN, w), clock: -> { @now += 0.5 })
    r.send(:boot_dmesg)
    err.string
  end

  # UX001 + UX018: a submitted turn is acknowledged once, as asking, never as done.
  def test_ux001_one_truthful_acknowledgement
    _, err, = repl(["hei"], context: "tty")
    lines = err.lines
    assert_equal 1, lines.grep(/asking/).size
    assert_operator lines.index { |l| l.include?("asking") }, :<, lines.index { |l| l.include?("answered") }
  end

  # UX003 + TODO "paste/multiline handling": << sends lines as one turn.
  def test_ux003_multiline_is_one_turn
    out, err, = repl(["<<", "first line", "second line", "", "/quit"])
    assert_equal 1, err.lines.grep(/answered/).size
    assert_match(/second line/, out)
  end

  # UX012: whitespace-only input causes no turn and no activity.
  def test_ux012_empty_input_is_nothing
    out, err, code = repl(["", "   ", "\t"])
    assert_equal "", out
    assert_equal 1, err.lines.size, "only the boot line"
    assert_equal 0, code
  end

  # UX010 + UX046 + UX058: help and completion read one table; help lists
  # canonical names only, no alias twice.
  def test_ux046_help_and_completion_share_the_registry
    out, = repl(["/help"])
    listed = out.lines.grep(%r{\A/}).map { |l| l.split.first }
    assert_equal Cli::Repl::COMMANDS.keys, listed
    Cli::Repl::ALIASES.each_key { |a| refute_includes listed, a }
  end

  # UX047: an alias runs its canonical command.
  def test_ux047_aliases_resolve_to_the_canonical_command
    _, err, code = repl(["/exit", "never asked"])
    refute_match(/answered/, err, "/exit is /quit: the session ended before the next line")
    assert_equal 0, code
  end

  # UX048 + UX053: an unknown command suggests a near one and runs nothing.
  def test_ux048_unknown_commands_suggest_and_never_execute
    out, err, code = repl(["/qiut", "hei"])
    assert_match(%r{cmd0: unknown command /qiut; did you mean /quit\?}, err)
    assert_match(/svar/, out, "the session went on: /qiut did not quit")
    assert_equal 1, code
  end

  # UX015: a failing command restores a usable prompt in the same process.
  def test_ux015_a_command_exception_leaves_the_repl_usable
    conv = conversation
    conv.memory.define_singleton_method(:type_counts) { raise IOError, "disk gone" }
    out, err, = repl(["/memory", "hei"], conv:)
    assert_match(%r{cmd0: /memory failed - IOError: disk gone}, err)
    assert_match(/svar/, out)
  end

  # UX017: the status names the model that answered, not a configured default.
  def test_ux017_the_answer_names_the_live_lane
    _, err, = repl(["hei"], env: {})
    assert_match(/answered by claude-cli:claude-sonnet-5-5/, err, "exploration routes to the fast tier's head")
  end

  # UX020 + TODO "PTY cancellation": ^C during a turn cancels it and the
  # prompt returns; nothing of the turn is saved.
  def test_ux020_an_interrupted_turn_is_cancelled_honestly
    conv = conversation
    conv.dispatch.define_singleton_method(:ask) { |*, **| raise Interrupt }
    _, err, = repl(["hei"], context: "tty", conv:)
    assert_match(/turn0: cancelled after \d+\.\ds; nothing was saved/, err)
    assert_empty conv.turns
  end

  # UX026 + UX042 + TODO "NO_COLOR/dumb terminal": no escape sequence on
  # either stream, so colour-off and pipes read the same bytes.
  def test_ux042_no_control_sequences_anywhere
    out, err, = repl(["hei", "/lanes", "/spend", "/model", "/bogus"])
    refute_match(/\e/, out + err)
  end

  # UX027 + UX055: in a pipe the boot is one plain line, no banner, no
  # decorative separators; a terminal gets the dmesg boot (boot_splash test).
  def test_ux027_one_boot_line_and_no_banner
    _, err, = repl([])
    assert_equal 1, err.lines.size
    assert_match(%r{\Arepl0: \S+ new session; next turn claude-cli:claude-opus-5-5; \d+ lanes down; /help\n\z}, err)
    refute_match(/[=#*]{3,}|[-]{4,}/, err)
  end

  # The boot is the kernel's: OpenBSD dmesg units closing on "root on
  # master0", then a blank line and the session status a pipe reads as
  # boot_line. A StringIO is no terminal, so the splash prints plain.
  def test_the_tty_boot_prints_the_openbsd_console_splash
    err = tty_boot
    lines = err.lines(chomp: true)
    assert_equal "master0 at mainbus0: pub5, model claude-cli:claude-opus-5-5", lines[0]
    assert_match(/\Ahost0 at mainbus0: \S+@\S+:\//, lines[1])
    assert_equal "root on master0", lines[2]
    assert_equal "", lines[3]
    assert_match(/\Arepl0: new session; \d+ lanes down; \/help\z/, lines[4])
    assert_equal 5, lines.size
    refute_match(/\e/, err, "a StringIO is no terminal: the splash prints plain")
  end

  # The console paints the kernel colours while it boots: 24-bit blue where
  # the terminal says truecolor, the palette pair elsewhere, plain under
  # NO_COLOR and off a terminal (pub4 trace/dmesg.rb console_paint).
  def test_the_boot_splash_paints_the_openbsd_console
    tty = StringIO.new
    def tty.tty? = true
    painted = "\e[37;48;2;0;0;255mroot on master0\e[0m"
    basic = "\e[37;44mroot on master0\e[0m"
    assert_equal painted, Cli::Terminal.boot_splash(["root on master0"], io: tty, colorterm: "truecolor")
    assert_equal painted, Cli::Terminal.boot_splash(["root on master0"], io: tty, colorterm: "24bit")
    assert_equal basic, Cli::Terminal.boot_splash(["root on master0"], io: tty)
    assert_equal "root on master0", Cli::Terminal.boot_splash(["root on master0"], io: tty, no_color: "1", colorterm: "truecolor")
    assert_equal "root on master0", Cli::Terminal.boot_splash(["root on master0"], io: StringIO.new, colorterm: "truecolor")
  end

  # UX028: the prompt names the repository it acts on, the OpenBSD operator
  # way: host:path$ (pub4 lib/face.rb shell_prompt).
  def test_ux028_the_prompt_names_the_repository
    w = world_for(PIN)
    r = Cli::Repl.new(world: w, context: "tty", conversation: conversation)
    prompt = r.send(:prompt_text)
    assert_equal "#{Cli::Prompt.shell_prompt(path: w.manifest.root, host: Socket.gethostname)} ", prompt
    assert_match(/#{Regexp.escape(File.basename(@root))}\$ \z/, prompt)
  end

  # The operator prompt's shape: host first name, home-relative path, the
  # deep path narrowed to where you are standing, the fallback host name.
  def test_the_operator_prompt_is_host_path
    home = Dir.home
    assert_equal "vm23:~/pub5$", Cli::Prompt.shell_prompt(path: File.join(home, "pub5"), host: "vm23.example.org")
    assert_equal "vm23:~$", Cli::Prompt.shell_prompt(path: home, host: "vm23")
    deep = File.join(home, "verylongdirname", "anotherlongdirname", "third")
    assert_match(/\Avm23:~\/\.\.\.\/anotherlongdirname\/third\$\z/, Cli::Prompt.shell_prompt(path: deep, host: "vm23"))
    assert_equal "openbsd:~$", Cli::Prompt.shell_prompt(path: home, host: "")
  end

  # UX030: help says there is no shell escape and what a plain line is.
  def test_ux030_help_distinguishes_master_from_the_shell
    out, = repl(["/help"])
    assert_match(/no shell escape; MASTER commands start with \//, out)
    assert_match(/Examples: /, out, "TODO: real help examples")
  end

  # UX031 + UX036 + TODO "result-first output": the reply comes first on
  # stdout, then one summary line on stderr whose first word is the outcome.
  def test_ux031_result_first_and_outcome_first
    out, err, = repl(["hei"])
    assert_equal "svar: \"hei\"\n", out
    assert_match(/\Aturn0: answered by /, err.lines.last)
    assert_equal 1, err.lines.grep(/turn0:/).size
  end

  # UX033: elapsed time is the measured duration.
  def test_ux033_elapsed_time_is_measured
    _, err, = repl(["hei"])
    assert_match(/answered by \S+ in 0\.5s, 4 in 2 out, \$0\.0010/, err)
  end

  # UX034 + TODO "actionable errors": a failure names its next action.
  def test_ux034_a_failure_says_what_to_do_next
    _, err, = repl(["crash"])
    assert_match(%r{turn0: FAILED no lane answered: .*; next: /lanes, or pin one with PUB5_MODEL}, err)
  end

  # UX037: every status line carries a stable subsystem prefix.
  def test_ux037_stable_prefixes
    _, err, = repl(["hei", "crash", "/bogus"])
    err.lines.each { |l| assert_match(/\A[a-z]+0: /, l) }
  end

  # UX023 + UX024 + TODO "width-aware wrapping": on a narrow terminal a long
  # status wraps under its prefix; outcome first, recovery action kept.
  def test_ux023_long_status_wraps_and_keeps_outcome_and_action
    message = "FAILED no lane answered: #{'word ' * 30}next: /lanes"
    rows = Cli::Terminal.line("turn", message, width: 40).lines(chomp: true)
    assert rows.first.start_with?("turn0: FAILED ")
    assert rows.join(" ").squeeze(" ").end_with?("next: /lanes"), "the recovery action is not cut away"
    rows.each { |r| assert_operator r.size, :<=, 40 }
    rows.drop(1).each { |r| assert r.start_with?("       ") }
    assert_equal 1, Cli::Terminal.line("turn", message).lines.size, "a pipe gets one whole line"
  end

  # UX043: a key in a reply or a status line never reaches the terminal.
  def test_ux043_secrets_are_redacted
    out, = repl(["secret please"])
    assert_match(/key \[secret\]/, out)
    refute_match(/sk-ant-/, out)
  end

  # Operator directive: ASCII marks in terminal output, letters untouched.
  def test_terminal_output_is_ascii_punctuation
    assert_equal "\"bla\" - ... -> \"ok\" a\u00E5", Cli::Terminal.ascii("\u201Cbla\u201D \u2013 \u2026 \u2192 \u00ABok\u00BB a\u00E5")
  end

  # UX041 + UX053: exit status matches the visible result.
  def test_ux041_ask_exit_codes
    assert_equal 0, ask(["hei"]).last
    assert_equal 1, ask(["crash"]).last
    assert_equal 64, ask([]).last
    assert_equal 64, ask(["--bogus", "x"]).last
    assert_equal 70, ask(["hei"], env: PIN.merge("PUB5_OFFLINE" => "1")).last
  end

  # UX045: -q drops the routine line, never a failure.
  def test_ux045_quiet_keeps_failures
    assert_equal "", ask(["-q", "hei"])[1]
    assert_match(/ask0: FAILED/, ask(["-q", "crash"])[1])
  end

  # UX056 + UX057 + TODO "JSON-only quiet mode": --json is one versioned
  # object on stdout; status stays on stderr.
  def test_ux056_json_output_is_versioned_and_alone
    out, err, = ask(["--json", "-q", "hei"])
    data = JSON.parse(out)
    assert_equal [1, "claude-cli:claude-opus-5-5", "svar: \u201Chei\u201D"], data.values_at("schema", "model", "text")
    assert_equal 1, out.lines.size
    assert_equal "", err
  end

  # UX057: in plain ask, stdout is the answer and nothing else.
  def test_ux057_stdout_is_the_answer_alone
    out, err, = ask([], input: "hei from stdin\n")
    assert_equal "svar: \"hei from stdin\"\n", out
    assert_match(/\Aask0: answered by /, err)
  end

  # TODO "session resume": a closed REPL comes back where it was; /new starts fresh.
  def test_session_resume_and_new
    repl(["hei", "how are you"])
    _, err, = repl([])
    assert_match(/resumed 2 turns/, err)
    repl(["/new"])
    assert_match(/new session/, repl([])[1])
  end

  # TODO "queued interruptions": lines typed during a turn run in order after it.
  def test_lines_queue_in_order_behind_a_turn
    out, = repl(%w[one two three])
    assert_equal %w[one two three], out.lines.map { |l| l[/"(\w+)"/, 1] }
  end

  # Memory and cognition on the turn path: a remembered fact rides the next
  # prompt, the operator's own words are auto-saved, the mind sees the turn.
  def test_memory_and_mind_follow_the_conversation
    conv = conversation
    out, = repl(["/remember deadline Friday", "never use awk in scripts", "/mind"], conv:)
    assert_match(/remembered deadline/, out)
    assert_equal 1, conv.memory.by_type("feedback").size
    assert_includes conv.send(:system_for, "x"), "deadline: Friday"
    assert_operator conv.mind.snapshot["workspace"].size, :>, 0
  end

  # TODO "measured startup": bin/master --boot prints the measured boot time,
  # and with no command in a pipe it prints usage and exits 0.
  def test_boot_time_is_measured_and_printed
    w = world(Core::ROOT, { exec: ["ruby"] })
    run = w.exec(RbConfig.ruby, File.join(Core::ROOT, "bin/master"), "--boot", "knobs", timeout: 60)
    assert_match(/\Amaster: boot \d+\.\d ms \(core \+ master\/commands\/knobs\.rb, pipe\)/, run.err)
    usage = w.exec(RbConfig.ruby, File.join(Core::ROOT, "bin/master"), stdin: "", timeout: 60)
    assert usage.ok?
    assert_match(/  repl  /, usage.err)
  end
end
