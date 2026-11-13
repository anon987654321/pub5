#!/usr/bin/env ruby
# frozen_string_literal: true

# Portable, interactive process killer. Match process command lines, ask for
# each PID separately, then signal only the processes the operator selects.
# Linux/Android use /proc; BSD/macOS use ps. No gem or shell interpolation.

require "optparse"

class Zap
  DEFAULT_SIGNAL = "KILL"
  PROTECTED_PIDS = [0, 1].freeze

  def initialize(argv, out: $stdout, err: $stderr, input: $stdin)
    @out = out
    @err = err
    @input = input
    @force = false
    @help = false
    @signal = Signal.list.fetch(DEFAULT_SIGNAL)
    @signal_label = "SIG#{DEFAULT_SIGNAL}"
    @pattern = nil
    @ps_path = nil
    parse(argv)
  end

  def run
    if @help
      @out.puts help_text
      return 0
    end

    matches = processes.select { |process| process[:command].include?(@pattern) }
    if matches.empty?
      @out.puts "zap: no processes match #{@pattern.inspect}"
      return 0
    end

    if openbsd? && @force && matches.any? { |process| vmd_process?(process) }
      @err.puts "zap: refusing forced vmd termination; use 'vmctl stop <vm>' for a guest or 'rcctl stop vmd' for the daemon"
      return 2
    end

    if openbsd? && matches.any? { |process| vmd_process?(process) }
      @err.puts "zap: vmd manages virtual machines; use vmctl to stop a guest cleanly"
    end

    matches.each do |process|
      next unless @force || confirm?(process)

      unless same_process?(process)
        @out.puts "zap: PID #{process[:pid]} changed or exited; skipped"
        next
      end

      signal_process(process)
    end
    0
  rescue OptionParser::ParseError, ArgumentError => e
    @err.puts "zap: #{e.message}"
    @err.puts help_text
    2
  rescue SystemCallError, IOError => e
    @err.puts "zap: #{e.message}"
    1
  rescue StandardError => e
    @err.puts "zap: #{e.message}"
    1
  end

  private

  def parse(argv)
    args = argv.dup

    # Keep the classic zap spelling: zap -TERM pattern and zap -9 pattern,
    # whether the signal appears before or after -f.
    signal_index = args.index do |arg|
      arg.match?(/\A-(?:[0-9]+|[A-Za-z][A-Za-z0-9]*)\z/) && !%w[-f -s -h].include?(arg)
    end
    set_signal(args.delete_at(signal_index).delete_prefix("-")) if signal_index

    parser = OptionParser.new do |opts|
      opts.banner = "usage: zap [-f] [-s SIGNAL] pattern"
      opts.on("-f", "--force", "Do not ask; signal every matching process") { @force = true }
      opts.on("-s SIGNAL", "--signal=SIGNAL", "Signal name or number (default: KILL)") do |value|
        set_signal(value)
      end
      opts.on("-h", "--help", "Show this help") { @help = true }
    end

    args = parser.parse(args)
    return if @help

    raise ArgumentError, "expected one search pattern" unless args.length == 1

    @pattern = args.first
    if @pattern.empty? || @pattern.match?(/[\x00-\x1f\x7f]/)
      raise ArgumentError, "search pattern must be non-empty and contain no control characters"
    end
  end

  def set_signal(value)
    token = value.to_s.sub(/\ASIG/i, "").upcase
    number = if token.match?(/\A[0-9]+\z/)
               Integer(token, 10)
             else
               Signal.list[token]
             end
    raise ArgumentError, "unknown signal: #{value}" unless number && Signal.list.value?(number)

    @signal = number
    name = Signal.list.find { |_, signal_number| signal_number == number }&.first
    @signal_label = name ? "SIG#{name}" : "signal #{number}"
  end

  def help_text
    <<~HELP
      usage: zap [-f] [-s SIGNAL] pattern

      Find process command lines containing pattern and ask about each PID.
      -f, --force       Skip questions and signal every match.
      -s, --signal NAME Signal name or number (default: KILL).
      -h, --help        Show this help.

      The classic -SIGNAL spelling is also accepted, for example: zap -TERM ruby.
      Linux/Android use /proc; OpenBSD, other BSDs and macOS use ps.
      Uses Ruby's standard library only.
    HELP
  end

  def openbsd?
    RUBY_PLATFORM.include?("openbsd")
  end

  def linux_procfs?
    RUBY_PLATFORM.include?("linux") && File.directory?("/proc/self") &&
      File.readable?("/proc/self/comm")
  rescue SystemCallError
    false
  end

  def processes
    linux_procfs? ? procfs_processes : ps_processes
  rescue SystemCallError
    ps_processes
  end

  def procfs_processes
    Dir.children("/proc").filter_map do |entry|
      next unless entry.match?(/\A[0-9]+\z/)

      pid = Integer(entry, 10)
      next if protected_pid?(pid)

      directory = File.join("/proc", entry)
      command = proc_command(directory)
      next if command.empty?

      { pid: pid, command: command, identity: proc_start_ticks(directory) }
    rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
      nil
    end
  end

  def proc_command(directory)
    raw = File.binread(File.join(directory, "cmdline"))
    command = raw.split("\0").reject(&:empty?).join(" ")
    return command unless command.empty?

    File.read(File.join(directory, "comm")).strip
  rescue SystemCallError
    ""
  end

  # Linux /proc/PID/stat field 22 prevents a recycled PID being signalled.
  def proc_start_ticks(directory)
    stat = File.read(File.join(directory, "stat"))
    tail = stat[(stat.rindex(")") + 2)..]
    tail&.split&.fetch(19, nil)
  rescue SystemCallError
    nil
  end

  def ps_processes
    output, status = IO.popen([ps_binary, "-ax", "-ww", "-o", "pid=", "-o", "command="], &:read), $?
    raise "ps failed (#{status&.exitstatus || "unknown status"})" unless status&.success?

    output.each_line.filter_map do |line|
      process = parse_ps_line(line)
      next unless process
      next if protected_pid?(process[:pid])

      process
    end
  end

  def ps_process(pid)
    output, status = IO.popen(
      [ps_binary, "-p", pid.to_s, "-ww", "-o", "pid=", "-o", "command="], &:read
    ), $?
    return unless status&.success?

    output.each_line.filter_map { |line| parse_ps_line(line) }.first
  end

  def parse_ps_line(line)
    match = line.match(/\A\s*([0-9]+)\s+(.+?)\s*\z/)
    return unless match

    pid = Integer(match[1], 10)
    command = match[2].strip
    return if command.empty?

    { pid: pid, command: command, identity: nil }
  end

  def ps_binary
    return @ps_path if @ps_path

    candidates = ["/bin/ps", "/usr/bin/ps", "/system/bin/ps"]
    candidates.concat(ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "ps") })
    @ps_path = candidates.uniq.find { |path| File.file?(path) && File.executable?(path) }
    raise "ps not found and /proc is unavailable" unless @ps_path

    @ps_path
  end

  def protected_pid?(pid)
    PROTECTED_PIDS.include?(pid) || pid == Process.pid || pid == Process.ppid
  end

  def command_name(command)
    File.basename(command.to_s.split.first.to_s)
  end

  def vmd_process?(process)
    name = command_name(process[:command])
    name == "vmd" || name.start_with?("vmd:")
  end

  def confirm?(process)
    @out.print "#{process[:pid]} #{process[:command]}? [y/N] "
    answer = @input.gets
    answer && answer.strip.match?(/\A(?:y|yes)\z/i)
  end

  def same_process?(original)
    pid = original.fetch(:pid)

    if linux_procfs? && original[:identity]
      directory = File.join("/proc", pid.to_s)
      current_identity = proc_start_ticks(directory)
      return false unless current_identity

      current_identity == original[:identity]
    else
      current = ps_process(pid)
      current && current[:command] == original[:command]
    end
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  def signal_process(process)
    Process.kill(@signal, process.fetch(:pid))
    @out.puts "zap: sent #{@signal_label} to PID #{process[:pid]}"
  rescue Errno::ESRCH
    @out.puts "zap: PID #{process[:pid]} already exited"
  rescue Errno::EPERM => e
    @err.puts "zap: cannot signal PID #{process[:pid]}: #{e.message}"
  end
end

exit Zap.new(ARGV).run if $PROGRAM_NAME == __FILE__
