#!/usr/bin/env ruby
# frozen_string_literal: true

# zap KEYWORD: send SIGKILL (9) to processes whose process name contains KEYWORD.
# Standard library only. Linux and Android use /proc; BSD and macOS use ps.

require "optparse"

class Zap
  SIGNAL = 9
  PROTECTED_PIDS = [0, 1].freeze

  def initialize(argv, out: $stdout, err: $stderr, process_provider: nil, signaler: nil,
                 platform: RUBY_PLATFORM)
    @out = out
    @err = err
    @process_provider = process_provider
    @signaler = signaler
    @platform = platform
    @dry_run = false
    @help = false
    @keyword = nil
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

    matches = processes.select { |process| process[:name].include?(@keyword) }
    if matches.empty?
      @out.puts "zap: no process name matches #{@keyword.inspect}"
      return 0
    end

    failures = 0
    matches.each do |process|
      if @dry_run
        @out.puts "zap: would kill -9 #{process[:pid]} #{process[:name]}"
        next
      end

      unless same_process?(process)
        @out.puts "zap: PID #{process[:pid]} changed or exited; skipped"
        next
      end

      failures += 1 unless kill_process(process)
    end

    @out.puts "zap: killed #{matches.length - failures} process(es) matching #{@keyword.inspect}" unless @dry_run
    failures.zero? ? 0 : 1
  rescue SystemCallError, IOError => e
    @err.puts "zap: #{e.message}"
    1
  rescue StandardError => e
    @err.puts "zap: #{e.message}"
    1
  end

  private

  def parse(argv)
    parser = OptionParser.new do |opts|
      opts.banner = "usage: zap [--dry-run] keyword"
      opts.on("--dry-run", "Show matching process names without killing them") { @dry_run = true }
      opts.on("-h", "--help", "Show this help") { @help = true }
    end

    args = parser.parse(argv.dup)
    return if @help

    raise ArgumentError, "expected one process-name keyword" unless args.length == 1

    @keyword = args.first
    if @keyword.empty? || @keyword.match?(/[\x00-\x1f\x7f]/)
      raise ArgumentError, "keyword must be non-empty and contain no control characters"
    end
  end

  def help_text
    <<~HELP
      usage: zap [--dry-run] keyword

      Kill every process whose process name contains keyword.
      The signal is always SIGKILL (9). No confirmation is requested.
      --dry-run  List matches without killing them.
      -h, --help Show this help.

      Linux and Android use /proc. OpenBSD, other BSDs and macOS use ps.
      Ruby standard library only; no zap package or gem required.
    HELP
  end

  def android?
    @platform.match?(/android/i)
  end

  def linux?
    @platform.match?(/linux/i)
  end

  def linux_procfs?
    linux? && File.directory?("/proc/self") && File.readable?("/proc/self/comm")
  rescue SystemCallError
    false
  end

  def processes
    return @process_provider.call if @process_provider

    linux_procfs? ? procfs_processes : ps_processes
  end

  def procfs_processes
    Dir.children("/proc").filter_map do |entry|
      next unless entry.match?(/\A[0-9]+\z/)

      pid = Integer(entry, 10)
      next if protected_pid?(pid)

      directory = File.join("/proc", entry)
      name = proc_name(directory)
      next if name.empty?

      start_ticks = proc_start_ticks(directory)
      next unless start_ticks

      { pid: pid, name: name, identity: [:procfs, start_ticks, name] }
    rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
      nil
    end
  end

  def proc_name(directory)
    File.read(File.join(directory, "comm")).chomp
  rescue SystemCallError
    ""
  end

  # Linux /proc/PID/stat field 22 is the process start time in clock ticks.
  def proc_start_ticks(directory)
    stat = File.read(File.join(directory, "stat"))
    tail = stat[(stat.rindex(")") + 2)..]
    tail&.split&.fetch(19, nil)
  rescue SystemCallError
    nil
  end

  def ps_processes
    output, status = run_ps(*ps_list_arguments)
    raise "ps failed (#{status.exitstatus || "unknown status"})" unless status.success?

    output.each_line.filter_map do |line|
      process = parse_ps_line(line)
      next unless process
      next if protected_pid?(process[:pid])

      process
    end
  end

  def ps_process(pid)
    output, status = run_ps(*ps_pid_arguments(pid))
    return unless status.success?

    output.each_line.filter_map { |line| parse_ps_line(line) }.first
  end

  def ps_list_arguments
    if android?
      ["-A", "-o", "PID,PPID,NAME"]
    else
      name_field = linux? ? "comm=" : "ucomm="
      ["-A", "-o", "pid=", "-o", "ppid=", "-o", "etime=", "-o", name_field]
    end
  end

  def ps_pid_arguments(pid)
    if android?
      ["-p", pid.to_s, "-o", "PID,PPID,NAME"]
    else
      name_field = linux? ? "comm=" : "ucomm="
      ["-p", pid.to_s, "-o", "pid=", "-o", "ppid=", "-o", "etime=", "-o", name_field]
    end
  end

  def run_ps(*arguments)
    output = IO.popen({ "LC_ALL" => "C" }, [ps_binary, *arguments], &:read)
    [output, $?]
  end

  def parse_ps_line(line)
    android? ? parse_android_ps_line(line) : parse_unix_ps_line(line)
  end

  # Android's Toybox ps has PID/PPID/NAME output columns. /proc is preferred;
  # this is the fallback for restricted or unusual Android environments.
  def parse_android_ps_line(line)
    fields = line.strip.split(/\s+/, 3)
    return unless fields.length == 3
    return unless fields[0].match?(/\A[0-9]+\z/) && fields[1].match?(/\A[0-9]+\z/)

    pid = Integer(fields[0], 10)
    ppid = Integer(fields[1], 10)
    name = fields[2].strip
    return if name.empty?

    { pid: pid, name: name, identity: [:ps_android, ppid, name] }
  end

  # etime and ucomm/comm describe the process itself, never its argument list.
  def parse_unix_ps_line(line)
    fields = line.strip.split(/\s+/, 4)
    return unless fields.length == 4
    return unless fields[0].match?(/\A[0-9]+\z/) && fields[1].match?(/\A[0-9]+\z/)

    pid = Integer(fields[0], 10)
    ppid = Integer(fields[1], 10)
    elapsed = fields[2]
    name = fields[3].strip
    return if name.empty?

    { pid: pid, name: name, identity: [:ps, ppid, elapsed, name] }
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
    PROTECTED_PIDS.include?(pid) || pid == Process.pid
  end

  def same_process?(original)
    identity = original[:identity]
    return false unless identity

    current = if identity.first == :procfs
                directory = File.join("/proc", original[:pid].to_s)
                ticks = proc_start_ticks(directory)
                name = proc_name(directory)
                ticks && { identity: [:procfs, ticks, name] }
              else
                ps_process(original[:pid])
              end
    current && current[:identity] == identity
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  def kill_process(process)
    pid = process.fetch(:pid)
    if @signaler
      @signaler.call(SIGNAL, pid)
    else
      Process.kill(SIGNAL, pid)
    end
    @out.puts "zap: killed -9 #{pid} #{process[:name]}"
    true
  rescue Errno::ESRCH
    @out.puts "zap: PID #{pid} already exited"
    true
  rescue Errno::EPERM => e
    @err.puts "zap: cannot kill PID #{pid}: #{e.message}"
    false
  end
end

exit Zap.new(ARGV).run if $PROGRAM_NAME == __FILE__
