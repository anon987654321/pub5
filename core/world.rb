# frozen_string_literal: true

require "open3"
require "erb"
require "uri"

module Core
  # World: the seven verbs that touch the outside, each checked against one
  # plugin's Manifest before it runs. A refused verb raises Refusal and is
  # appended to the ledger; an effect that ran (write, exec, git, net, llm) is
  # appended too, so the ledger is the record of what a run did.
  class World
    Run = Data.define(:argv, :status, :out, :err, :timed_out) do
      def ok? = !timed_out && status&.success?
    end

    TERM_GRACE = 2

    attr_reader :manifest, :ledger

    def initialize(manifest:, ledger:, knobs: Knobs.default, transport: HTTP, models: nil)
      @manifest = manifest
      @ledger = ledger
      @knobs = knobs
      @transport = transport
      @models = models
    end

    def read(path) = File.binread(allow(:read, path))

    def write(path, content, mode: nil)
      full = allow(:write, path)
      Atomic.write(full, content, mode:)
      @ledger.append(:effect, verb: "write", plugin: @manifest.name, path: relative(full), bytes: content.bytesize)
      full
    end

    def render(template, locals = {})
      ERB.new(File.read(allow(:render, template)), trim_mode: "-").result_with_hash(locals)
    end

    def exec(*argv, timeout: @knobs.fetch("PUB5_EXEC_TIMEOUT"), chdir: @manifest.root, stdin: nil)
      allow(:exec, File.basename(argv.first.to_s))
      run = spawn(argv, timeout:, chdir:, stdin:)
      @ledger.append(:effect, verb: "exec", plugin: @manifest.name, argv:, exit: run.status&.exitstatus, timed_out: run.timed_out)
      run
    end

    def git(subcommand, *args, timeout: @knobs.fetch("PUB5_EXEC_TIMEOUT"))
      allow(:git, subcommand.to_s)
      argv = ["git", "-C", @manifest.root, subcommand.to_s, *args]
      run = spawn(argv, timeout:, chdir: @manifest.root, stdin: nil)
      @ledger.append(:effect, verb: "git", plugin: @manifest.name, argv: [subcommand.to_s, *args], exit: run.status&.exitstatus)
      run
    end

    def net(method, url, **options)
      allow(:net, URI(url).host.to_s)
      reply = @transport.request(method, url, timeout: @knobs.fetch("PUB5_HTTP_TIMEOUT"), **options)
      @ledger.append(:effect, verb: "net", plugin: @manifest.name, method: method.to_s, host: URI(url).host, status: reply.status)
      reply
    end

    def llm(provider:, **request)
      allow(:llm, provider.to_s)
      client = LLM.new(models: @models || Registry.load(:models), knobs: @knobs, ledger: @ledger, transport: @transport)
      client.complete(provider:, **request)
    end

    private

    def allow(verb, target)
      @manifest.check!(verb, target)
    rescue Refusal => e
      @ledger.append(:refusal, verb: verb.to_s, plugin: @manifest.name, target: target.to_s, reason: e.message)
      raise
    end

    def relative(full) = full.delete_prefix("#{@manifest.root}/")

    # argv only, never a shell string; a child that outlives its timeout gets
    # TERM, then KILL after TERM_GRACE, and the run reports timed_out.
    def spawn(argv, timeout:, chdir:, stdin:)
      Open3.popen3(*argv, chdir:) do |input, out, err, thread|
        input.write(stdin) if stdin
        input.close
        readers = [Thread.new { out.read }, Thread.new { err.read }]
        timed_out = thread.join(timeout).nil?
        terminate(thread) if timed_out
        Run.new(argv:, status: thread.value, out: readers[0].value, err: readers[1].value, timed_out:)
      end
    rescue Errno::ENOENT => e
      Run.new(argv:, status: nil, out: "", err: e.message, timed_out: false)
    end

    def terminate(thread)
      Process.kill("TERM", thread.pid)
      Process.kill("KILL", thread.pid) unless thread.join(TERM_GRACE)
    rescue Errno::ESRCH
      nil
    end
  end
end
