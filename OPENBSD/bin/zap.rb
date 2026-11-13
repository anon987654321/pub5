#!/usr/bin/env ruby
# frozen_string_literal: true

# Portable process terminator. Uses /proc on Linux/Android and ps on BSD/macOS.
# It uses only Ruby's standard library and never interpolates shell commands.

require "optparse"

class Zap
  GRACE_SECONDS = 2.0
  POLL_SECONDS = 0.05
  PROTECTED_PIDS = [0, 1].freeze

  def initialize(argv, out: $stdout, err: $stderr, input: $stdin)
    @out = out
    @err = err
    @input = input
    @force = false
    @help = false
    @name = nil
    @ps_path = nil
    parse(argv)
  end

  def run
    if @help
      @out.puts help_text
      return 0
    end

    if openbsd? && @name == "vmd"
      @err.puts "zap: refusing to signal vmd; use 'vmctl stop <vm>' for a guest or 'rcctl stop vmd' for the daemon"
      return 2
    end

    matches = processes.select { |process| matches_name?(process[:name]) }
    if matches.empty?
      @out.puts "zap: no process named #{@name}"
      return 0
    end

    matches.each { |process| @out.puts "#{process[:pid]}  #{process[:name]}" }
    return 1 unless @force || confirm?

    failures = matches.filter_map { |process| stop(process) }
    failures.each { |message| @err.puts "zap: #{message}" }
    failures.empty? ? 0 : 1
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
    parser = OptionParser.new do |opts|
      opts.banner = "usage: ruby zap.rb [-f|--force] process-name"
      opts.on("-f", "--force", "Skip confirmation; still try TERM before KILL") { @force = true }
      opts.on("-h", "--help", "Show this help") { @help = true }
    end

    args = parser.parse(argv.dup)
    return if @help

    raise ArgumentError, "expected one process name" unless args.length == 1

    @name = args.first
    unless @name.match?(/\A[A-Za-z0-9_.:-]{1,128}\z/)
      raise ArgumentError, "invalid process name"
    end
  end

  def help_text
    <<~HELP
      usage: ruby zap.rb [-f|--force] process-name

      Stop processes whose command name matches process-name.
      -f, --force  Skip confirmation; send TERM, then KILL after #{GRACE_SECONDS.to_i} seconds if needed.
      -h, --help   Show this help.

      Linux and Android use /proc. BSD and macOS use ps.
      No package, gem, root privilege or shell is required.
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
  end

  def procfs_processes
    Dir.children("/proc").filter_map do |entry|
      next unless entry.match?(/\A[0-9]+\z/)

      pid = Integer(entry, 10)
      next if protected_pid?(pid)

      directory = File.join("/proc", entry)
      name = File.read(File.join(directory, "comm")).strip
      next if name.empty?

      { pid: pid, name: name, identity: proc_start_ticks(directory) }
    rescue Errno::ENOENT, Errno::EACCES, Errno::ESRCH
      nil
    end
  end

  # /proc/PID/stat field 22 is the process start time in clock ticks. Compare it
  # before escalation so a recycled PID is never mistaken for the original task.
  def proc_start_ticks(directory)
    stat = File.read(File.join(directory, "stat"))
    tail = stat[(stat.rindex(")") + 2)..]
    tail&.split&.fetch(19, nil)
  rescue SystemCallError
    nil
  end

  def ps_processes
    output, status = IO.popen([ps_binary, "-ax", "-o", "pid=", "-o", "comm="], &:read), $?
    raise "ps failed (#{status&.exitstatus || "unknown status"})" unless status&.success?

    output.each_line.filter_map do |line|
      record = parse_ps_line(line)
      next unless record
      next if protected_pid?(record[:pid])

      record
    end
  end

  def parse_ps_line(line)
    match = line.match(/\A\s*([0-9]+)\s+(.+?)\s*\z/)
    return unless match

    pid = Integer(match[1], 10)
    name = File.basename(match[2])
    return if name.empty?

    { pid: pid, name: name, identity: nil }
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

  def matches_name?(name)
    name == @name || name.start_with?("#{@name}:")
  end

  def confirm?
    @out.print "Terminate #{@name}? [y/N] "
    answer = @input.gets
    answer && answer.strip.match?(/\A(?:y|yes)\z/i)
  end

  def stop(process)
    pid = process.fetch(:pid)
    Process.kill("TERM", pid)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GRACE_SECONDS
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return nil unless same_process?(process)

      sleep POLL_SECONDS
    end

    return nil unless same_process?(process)

    Process.kill("KILL", pid)
    nil
  rescue Errno::ESRCH
    nil
  rescue Errno::EPERM => e
    "cannot signal pid #{pid}: #{e.message}; run as the process owner or an authorised administrator"
  end

  def same_process?(original)
    pid = original.fetch(:pid)

    if linux_procfs? && original[:identity]
      directory = File.join("/proc", pid.to_s)
      current = proc_start_ticks(directory)
      return false unless current

      current == original[:identity]
    else
      current = ps_process(pid)
      current && matches_name?(current[:name])
    end
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  def ps_process(pid)
    output, status = IO.popen([ps_binary, "-p", pid.to_s, "-o", "pid=", "-o", "comm="], &:read), $?
    return unless status&.success?

    output.each_line.filter_map { |line| parse_ps_line(line) }.first
  end
end

exit Zap.new(ARGV).run if $PROGRAM_NAME == __FILE__
