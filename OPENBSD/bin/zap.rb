#!/usr/bin/env ruby
# frozen_string_literal: true

# Ruby port of OpenBSD sysutils/zap: find command lines by substring, ask
# before signalling each process, and keep process discovery shell-free.
# Standard library only. Linux uses /proc; OpenBSD and other BSDs use ps.

require "optparse"

class Zap
  DEFAULT_SIGNAL = "TERM"
  PROTECTED_PIDS = [0, 1].freeze
  # These are host-control processes, not ordinary application daemons.
  # Manage VM guests with vmctl; never terminate the VMM/control console here.
  OPENBSD_PROTECTED_COMMANDS = %w[vmd vmctl cu].freeze

  def initialize(argv, out: $stdout, err: $stderr, input: $stdin,
                 process_provider: nil, signaler: nil, platform: RUBY_PLATFORM)
    @out = out
    @err = err
    @input = input
    @process_provider = process_provider
    @signaler = signaler
    @platform = platform
    @force = false
    @dry_run = false
    @help = false
    @signal = Signal.list.fetch(DEFAULT_SIGNAL)
    @signal_label = "SIG#{DEFAULT_SIGNAL}"
    @pattern = nil
    @ps_path = nil
    @parse_error = nil
    begin
      parse(argv)
    rescue OptionParser::ParseError, ArgumentError => e
      @parse_error = e
    end
  end

  def run
    if @parse_error
      @err.puts "zap: #{@parse_error.message}"
      @err.puts help_text
      return 2
    end

    if @help
      @out.puts help_text
      return 0
    end

    matches = processes.select do |process|
      @pattern.nil? || process[:command].include?(@pattern)
    end

    # Do not let one protected VMM process prevent safe cleanup of unrelated
    # matches (or the no-pattern interactive mode). Protected processes are
    # reported and skipped; an all-protected selection is a refusal.
    protected_matches = matches.select { |process| protected_process?(process) }
    protected_matches.each do |process|
      name = command_name(process[:command])
      message = if name == "vmd"
                  "use 'vmctl stop <vm>' for a guest or 'rcctl stop vmd' for the daemon"
                elsif name == "vmctl"
                  "use vmctl deliberately to manage the guest"
                else
                  "leave the active VM console session to its operator"
                end
      @err.puts "zap: refusing to signal #{name}; #{message}"
    end
    matches -= protected_matches

    if matches.empty?
      @out.puts(@pattern ? "zap: no processes match #{@pattern.inspect}" : "zap: no signalable processes")
      return protected_matches.empty? ? 0 : 2
    end

    failed = false
    matches.each do |process|
      if @dry_run
        @out.puts "zap: would send #{@signal_label} to PID #{process[:pid]} #{process[:command]}"
        next
      end

      next unless @force || confirm?(process)

      unless same_process?(process)
        @out.puts "zap: PID #{process[:pid]} changed or exited; skipped"
        next
      end

      failed = true unless signal_process(process)
    end
    failed ? 1 : 0
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

    # Keep the classic spelling: zap -TERM pattern and zap -9 pattern,
    # whether the signal appears before or after -f.
    signal_index = args.index do |arg|
      arg.match?(/\A-(?:[0-9]+|[A-Za-z][A-Za-z0-9]*)\z/) &&
        !%w[-f -s -h].include?(arg)
    end
    set_signal(args.delete_at(signal_index).delete_prefix("-")) if signal_index

    parser = OptionParser.new do |opts|
      opts.banner = "usage: zap [-f] [-s SIGNAL] [--dry-run] [pattern]"
      opts.on("-f", "--force", "Do not ask; signal every matching process") { @force = true }
      opts.on("-s SIGNAL", "--signal=SIGNAL", "Signal name or number (default: TERM)") do |value|
        set_signal(value)
      end
      opts.on("--dry-run", "List matches without signalling") { @dry_run = true }
      opts.on("-h", "--help", "Show this help") { @help = true }
    end

    args = parser.parse(args)
    return if @help

    raise ArgumentError, "expected at most one search pattern" if args.length > 1

    @pattern = args.first
    raise ArgumentError, "force mode requires an explicit search pattern" if @force && @pattern.nil?
    if @pattern && (@pattern.empty? || @pattern.match?(/[\x00-\x1f\x7f]/))
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
      usage: zap [-f] [-s SIGNAL] [--dry-run] [pattern]

      Find all processes, or command lines containing pattern, and ask about each PID.
      -f, --force        Skip questions and signal every matching process.
      -s SIGNAL          Signal name or number (default: TERM).
      --dry-run          List matches without sending signals.
      -h, --help         Show this help.

      The classic -SIGNAL spelling is also accepted, for example: zap -TERM ruby.
      Linux/Android use /proc; OpenBSD, other BSDs and macOS use ps.
      Uses Ruby's standard library only.
      On OpenBSD, vmd, vmctl and cu are protected; use VM recovery controls.
    HELP
  end

  def openbsd?
    @platform.include?("openbsd")
  end

  def linux_procfs?
    @platform.include?("linux") && File.directory?("/proc/self") &&
      File.readable?("/proc/self/comm")
  rescue SystemCallError
    false
  end

  def processes
    return @process_provider.call if @process_provider

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

      start_ticks = proc_start_ticks(directory)
      {
        pid: pid,
        command: command,
        identity: start_ticks && [:procfs, start_ticks]
      }
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
    arguments = if android?
                   ["-A", "-o", "PID,PPID,STIME:19,ARGS", "-w"]
                 else
                   ["-ax", "-ww", "-o", "pid=", "-o", "ppid=", "-o", "lstart=", "-o", "command="]
                 end
    output, status = run_ps(*arguments)
    raise "ps failed (#{status.exitstatus || "unknown status"})" unless status.success?

    output.each_line.filter_map do |line|
      process = parse_ps_line(line)
      next unless process
      next if protected_pid?(process[:pid])

      process
    end
  end

  def ps_process(pid)
    arguments = if android?
                   ["-p", pid.to_s, "-o", "PID,PPID,STIME:19,ARGS", "-w"]
                 else
                   ["-p", pid.to_s, "-ww", "-o", "pid=", "-o", "ppid=", "-o", "lstart=", "-o", "command="]
                 end
    output, status = run_ps(*arguments)
    return unless status.success?

    output.each_line.filter_map { |line| parse_ps_line(line) }.first
  end

  def run_ps(*arguments)
    output = IO.popen({ "LC_ALL" => "C" }, [ps_binary, *arguments], &:read)
    [output, $?]
  end

  def parse_ps_line(line)
    android? ? parse_android_ps_line(line) : parse_bsd_ps_line(line)
  end

  # Toybox exposes STIME as a 19-column timestamp on Android. The two-part
  # date is parsed before the remaining command line; no shell or external
  # parser is involved.
  def parse_android_ps_line(line)
    match = line.match(/\A\s*(\d+)\s+(\d+)\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)\z/)
    return unless match

    pid = Integer(match[1], 10)
    ppid = Integer(match[2], 10)
    start = match[3]
    command = match[4].strip
    return if command.empty?

    { pid: pid, command: command, identity: [:ps, ppid, start, command] }
  end

  # BSD/macOS lstart is an exact, human-readable start timestamp. It avoids
  # the minute-resolution PID-reuse ambiguity of ps's short "start" field.
  def parse_bsd_ps_line(line)
    fields = line.strip.split(/\s+/, 8)
    return unless fields.length == 8
    return unless fields[0].match?(/\A[0-9]+\z/) && fields[1].match?(/\A[0-9]+\z/)

    pid = Integer(fields[0], 10)
    ppid = Integer(fields[1], 10)
    start = fields[2, 5].join(" ")
    command = fields[7].to_s.strip
    return if command.empty?

    { pid: pid, command: command, identity: [:ps, ppid, start, command] }
  end

  def android?
    @platform.match?(/android/i)
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
    token = command.to_s.lstrip.split(/\s+/, 2).first.to_s
    File.basename(token).sub(/:\z/, "")
  end

  def protected_process?(process)
    openbsd? && OPENBSD_PROTECTED_COMMANDS.include?(command_name(process[:command]))
  end

  def confirm?(process)
    @out.print "#{process[:pid]} #{process[:command]}? [y/N] "
    answer = @input.gets
    answer && answer.strip.match?(/\A(?:y|yes)\z/i)
  end

  def same_process?(original)
    identity = original[:identity]
    return false unless identity

    pid = original.fetch(:pid)
    case identity.first
    when :procfs
      directory = File.join("/proc", pid.to_s)
      current_ticks = proc_start_ticks(directory)
      current_command = proc_command(directory)
      current_ticks == identity[1] && current_command == original[:command]
    when :ps
      current = ps_process(pid)
      current && current[:identity] == identity
    else
      false
    end
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  def signal_process(process)
    pid = process.fetch(:pid)
    if @signaler
      @signaler.call(@signal, pid)
    else
      Process.kill(@signal, pid)
    end
    @out.puts "zap: sent #{@signal_label} to PID #{pid}"
    true
  rescue Errno::ESRCH
    @out.puts "zap: PID #{pid} already exited"
    true
  rescue Errno::EPERM => e
    @err.puts "zap: cannot signal PID #{pid}: #{e.message}"
    false
  end
end

exit Zap.new(ARGV).run if $PROGRAM_NAME == __FILE__
