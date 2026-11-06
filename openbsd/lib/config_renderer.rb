# frozen_string_literal: true

require "digest"
require_relative "../../core/core"

module OpenBSD
  # Render serving configuration from the validated registry. The proven
  # files are immutable acceptance fixtures: writes fail closed on any drift.
  class ConfigRenderer
    class Failure < StandardError; end

    attr_reader :root

    def initialize(root: Core::ROOT, registry: nil, apps: nil)
      @root = File.expand_path(root)
      @registry = registry || Core::Registry.load(:openbsd)
      @apps = apps || Core::Registry.load(:apps).fetch("apps")
    end

    def render
      assert_serving_facts!
      files = { "relayd.conf" => render_relayd, "pf.conf" => render_pf }
      @registry.fetch("rc").fetch("scripts").each do |name, script|
        files[File.join("rc.d", safe_script_name(name))] = render_rc(script)
      end
      files
    end

    def check!
      files = render
      prove_file_set!(files)
      files.each do |relative, expected|
        compare!(relative, "proven", expected, read(File.join("openbsd", "proven", relative)))
        compare!(relative, "generated", expected, read(File.join("openbsd", "etc", relative)))
      end
      true
    end

    # Only the generated mirror is writable. The proven fixtures and live host
    # are never modified by this command.
    def write!
      files = render
      prove_file_set!(files)
      files.each do |relative, expected|
        target = File.join(root, "openbsd", "etc", relative)
        refuse_symlink_ancestors!(target)
        Core::Atomic.write(target, expected, mode: existing_mode(target))
      end
      check!
      true
    end

    private

    def read(relative)
      path = File.join(root, relative)
      raise Failure, "missing file: #{relative}" unless File.file?(path)
      raise Failure, "symlink refused: #{relative}" if File.symlink?(path)
      File.binread(path)
    end

    def existing_mode(path)
      File.exist?(path) ? File.stat(path).mode & 0o7777 : 0o644
    end

    def refuse_symlink_ancestors!(target)
      current = File.dirname(target)
      stop = File.join(root, "openbsd")
      loop do
        raise Failure, "symlink directory refused: #{current}" if File.symlink?(current)
        break if current == stop || current == File.dirname(current)
        current = File.dirname(current)
      end
      raise Failure, "symlink destination refused: #{target}" if File.symlink?(target)
    end

    def safe_script_name(name)
      value = name.to_s
      raise Failure, "unsafe rc.d script name: #{value.inspect}" unless value.match?(/\A[a-z0-9_]+\z/)
      value
    end

    def directory_files(path)
      raise Failure, "missing directory: #{path.delete_prefix("#{root}/")}" unless File.directory?(path)
      raise Failure, "symlink directory refused: #{path}" if File.symlink?(path)
      Dir.children(path).select { |name| File.file?(File.join(path, name)) }.sort
    end

    def prove_file_set!(files)
      scripts = @registry.fetch("rc").fetch("scripts").keys.map(&:to_s).sort
      proven = directory_files(File.join(root, "openbsd", "proven", "rc.d"))
      generated = directory_files(File.join(root, "openbsd", "etc", "rc.d"))
      raise Failure, "registry/proven rc.d names differ" unless scripts == proven
      raise Failure, "registry/generated rc.d names differ" unless scripts == generated
      expected = ["pf.conf", "relayd.conf"] + scripts.map { |name| File.join("rc.d", name) }
      raise Failure, "renderer output set differs" unless expected.sort == files.keys.sort
    end

    def compare!(relative, label, expected, actual)
      return if expected == actual
      raise Failure,
            "#{label} drift at openbsd/#{relative}: expected sha256=#{Digest::SHA256.hexdigest(expected)}, actual sha256=#{Digest::SHA256.hexdigest(actual)}"
    end

    def assert_serving_facts!
      relay = @registry.fetch("relayd")
      ports = @apps.each_with_object({}) do |(name, app), result|
        result[name.to_s] = Integer(app.fetch("port")) if app.key?("port")
      end
      tables = relay.fetch("tables").map(&:to_s).sort
      raise Failure, "relayd tables differ from app registry" unless tables == ports.keys.sort

      forwards = relay.fetch("relay").fetch("forwards")
      by_app = forwards.to_h { |row| [row.fetch("app").to_s, row] }
      raise Failure, "duplicate relayd forwards" unless by_app.length == forwards.length
      ports.each do |name, port|
        row = by_app[name]
        raise Failure, "missing relayd forward for #{name}" unless row
        raise Failure, "relayd port for #{name} disagrees with app registry" unless Integer(row.fetch("port")) == port
      end

      @registry.fetch("rc").fetch("scripts").each do |name, script|
        next unless %w[falcon puma].include?(script.fetch("shape"))
        app = @apps.fetch(name.to_s) { raise Failure, "rc.d script has no app registry row: #{name}" }
        row = script.fetch("rows").find { |entry| entry.fetch("line").match?(/\APORT=\d+\z/) }
        raise Failure, "rc.d script has no PORT line: #{name}" unless row
        port = Integer(row.fetch("line").match(/\APORT=(\d+)\z/)[1])
        raise Failure, "rc.d PORT for #{name} disagrees with app registry" unless port == Integer(app.fetch("port"))
      end
    end

    def render_relayd
      relay = @registry.fetch("relayd")
      protocol = relay.fetch("protocol")
      backend = relay.fetch("relay")
      lines = []
      lines.concat(relay.fetch("prelude"))
      lines << ""
      relay.fetch("tables").each { |name| lines << "table <#{name}> { 127.0.0.1 }" }
      lines << ""
      lines << protocol.fetch("header")
      protocol.fetch("entries").each do |entry|
        entry.fetch("notes", []).each { |note| lines << "  #{note}" }
        lines << (entry.fetch("kind") == "blank" ? "" : "  #{entry.fetch('line')}")
      end
      lines << "}"
      lines << ""
      lines.concat(backend.fetch("notes", []))
      lines << "" unless backend.fetch("notes", []).empty?
      lines << backend.fetch("header")
      backend.fetch("inner_notes", []).each { |note| lines << "  #{note}" }
      lines << "  #{backend.fetch('listen')}"
      lines << "  #{backend.fetch('protocol')}"
      backend.fetch("forwards").each do |row|
        lines << %(  forward to <#{row.fetch("app")}> port #{row.fetch("port")} check http "#{row.fetch("path")}" code #{row.fetch("code")})
      end
      lines << "}"
      "#{lines.join("\n")}\n"
    end

    def render_pf
      policy = @registry.fetch("pf")
      lines = []
      policy.fetch("vars").each_value do |entry|
        lines.concat(entry.fetch("notes", []))
        lines.concat(entry.fetch("raw"))
      end
      policy.fetch("rules").each do |entry|
        if entry.fetch("kind") == "blank"
          lines << ""
        else
          lines.concat(entry.fetch("notes", []))
          lines.concat(entry.fetch("raw"))
        end
      end
      "#{lines.join("\n")}\n"
    end

    def render_rc(script)
      script.fetch("rows").map { |row| row.fetch("line").to_s }.join("\n") + "\n"
    end
  end
end
