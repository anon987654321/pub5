# frozen_string_literal: true

require "open3"

module Master
  module CLI
    # Detachable MASTER sessions in screen(1)'s own vocabulary, kept by tmux on
    # a socket of their own so the list holds MASTER's sessions and no others.
    #
    #   bin/master -S name   start session name running bin/master, or attach it
    #   bin/master -ls       list sessions
    #   bin/master -r [name] resume name; with several and no name, pick one
    #   bin/master -k name   end session name
    #
    # Inside a session, Ctrl-b d detaches; the work keeps running.
    class Screen
      SOCKET = "master"
      DEFAULT = "master"
      HANDLERS = { "-S" => :start, "-ls" => :list, "-r" => :resume, "-k" => :kill }.freeze
      FORMAT = "\#{session_name}\t\#{session_attached}\t\#{session_created}\t\#{pane_current_command}"
      Session = Struct.new(:name, :attached, :created, :command, keyword_init: true)

      # What the commands touch outside Ruby: tmux, the terminal and exec.
      Host = Struct.new(:tmux, :input, :out, :exec, keyword_init: true) do
        def self.default
          tmux = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "tmux") }
                            .find { |path| File.executable?(path) }
          new(tmux:, input: $stdin, out: $stdout, exec: Kernel.method(:exec))
        end
      end

      def self.flag?(arg) = HANDLERS.key?(arg)

      def initialize(master:, root:, host: Host.default)
        @master = master
        @root = root
        @host = host
      end

      # Returns an exit status, or replaces the process with tmux.
      def run(argv)
        verb, name = argv
        return refuse("tmux not found; install it (pkg_add tmux, brew install tmux)", 78) unless @host.tmux

        send(HANDLERS.fetch(verb), name)
      end

      def sessions
        output, status = tmux_capture("list-sessions", "-F", FORMAT)
        return [] unless status.success?

        output.lines.map do |line|
          name, attached, created, command = line.chomp.split("\t", 4)
          Session.new(name:, attached: attached.to_i.positive?, created: Time.at(created.to_i), command:)
        end
      end

      def list(_name = nil)
        rows = sessions
        say("#{rows.size} session#{'s' unless rows.size == 1}")
        rows.each_with_index { |row, index| say("#{index + 1} #{describe(row)}") }
        say("start one with bin/master -S <name>") if rows.empty?
        0
      end

      def start(name)
        name = safe(name)
        return attach(name) if sessions.any? { |row| row.name == name }

        tmux_exec("new-session", "-s", name, "-c", @root, @master)
      end

      def resume(name)
        rows = sessions
        return refuse("no sessions; start one with bin/master -S <name>", 1) if rows.empty?

        chosen = choose(rows, name)
        return refuse("no session #{name || 'chosen'}; bin/master -ls lists them", 1) unless chosen

        attach(chosen.name)
      end

      def kill(name)
        output, status = tmux_capture("kill-session", "-t", safe(name))
        return refuse("no session #{safe(name)}: #{output.strip}", 1) unless status.success?

        say("ended #{safe(name)}")
        0
      end

      private

      def choose(rows, name)
        return rows.find { |row| row.name == safe(name) } if name
        return rows.first if rows.one?

        ask(rows)
      end

      def ask(rows)
        list
        @host.out.print("screen0: resume which? ")
        answer = @host.input.gets.to_s.strip
        rows[answer.to_i - 1] if answer.match?(/\A\d+\z/) && answer.to_i.between?(1, rows.size)
      end

      def attach(name) = tmux_exec("attach-session", "-t", name)

      def tmux_capture(*argv) = Open3.capture2e(@host.tmux, "-L", SOCKET, *argv)

      # tmux refuses to nest under $TMUX; this socket is a different server.
      def tmux_exec(*argv) = @host.exec.call({ "TMUX" => nil }, @host.tmux, "-L", SOCKET, *argv)

      def describe(row)
        state = row.attached ? "attached" : "detached"
        "#{row.name} (#{state}, since #{row.created.strftime('%Y-%m-%d %H:%M')}, running #{row.command})"
      end

      def safe(name)
        cleaned = name.to_s.gsub(/[^A-Za-z0-9._-]/, "-")
        cleaned.empty? ? DEFAULT : cleaned
      end

      def say(message) = @host.out.puts("screen0: #{message}")

      def refuse(message, code)
        say(message)
        code
      end
    end
  end
end
