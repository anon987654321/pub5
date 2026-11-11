# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "shellwords"
require_relative "backlog_classify"
require_relative "backlog_reader"
require_relative "backlog_store"
require_relative "../lib/fix/task_contract"

# The backlog generator: one YAML row per checkbox item in the root TODO.md.
#
# TODO.md is prose that a session reads, and /fix's work intake wants rows it
# can rank, gate and receipt. Hand-copying the items into a second file
# re-creates the staleness problem that file warns about — an entry outliving
# its source — so the rows are generated, TODO.md stays the one source, and
# the store's --check fails when the generated file no longer matches it.
#
# id, text and section are mechanical extractions. tree, kind and size are
# derived heuristics from the item's own words: a starting classification, and
# a deliberate curation of their rules belongs in Backlog::Classify, not in
# the output file. done_when carries the first runnable command the item
# names, verbatim; an item that names none carries the reason instead. A row
# whose checkbox is checked off is landed evidence and leaves the backlog in
# the same read.
module Backlog
  MASTER_ROOT = File.expand_path("..", __dir__)
  SOURCE = File.expand_path("../TODO.md", MASTER_ROOT)
  DEST = File.join(MASTER_ROOT, "data", "backlog.yml")

  TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ cross operator].freeze
  KINDS = %w[verify mechanical design product operator-only plan].freeze
  SIZES = %w[s m l].freeze

  ROOTED_PATH = %r{(?:MASTER|RAILS|OPENBSD|STUDIO|BIZ|pub4)/[\w.\-]+(?:/[\w.\-]+)*}
  REL_PATH = %r{
    (?<![\w/])(?:lib|bin|data|docs|tools|checks|test|law|man|contracts|
    plugins|app|config|knowledge|public|storage|etc|usr|home|var|dev|db|
    script)/[\w.\-]+(?:/[\w.\-]+)*
  }x
  FILE_PATH = /\b[\w\-]+\.(?:yml|yaml|rb|md|json|erb|scss|js|mjs|png|conf|lock|csv|webp|wav)\b/

  module_function

  def generate(source: SOURCE)
    entries = parse(source).map { |item| entry(item) }
    raise "no checkbox items found in #{source}: a parse that reads nothing says nothing" if entries.empty?

    assign_ids!(entries)
  end

  def parse(source)
    raise "missing source #{source}" unless File.file?(source)

    reader = Reader.new
    File.foreach(source) { |raw| reader.read(raw.chomp) }
    reader.finish
  end

  def entry(item)
    text = item[:prose].join(" ")
    section = section_of(item)
    kind = Classify.kind(item:, text:, section:)
    command = first_command(item)

    {
      id: nil,
      text:,
      section:,

      tree: owner(item:, text:, section:, kind:),
      kind:,
      size: size_of(text),
      scope_paths: scope_paths(text),

      done_when: command,
      done_when_note: note_for(item:, command:, kind:),
    }
  end

  def section_of(item)
    # A row above any ## heading takes the document title as its section.
    [item[:h2] || item[:h1], item[:h3]].compact.join(" — ")
  end

  # The tree is the tree the text speaks for; a tie or a plan speaks for all.
  def owner(item:, text:, section:, kind:)
    return "operator" if kind == "operator-only"
    return "cross" if item[:plan]

    counts = Classify.signal_counts(text, section)
    top = counts.values.max
    return "cross" if top.nil? || top.zero?

    leaders = counts.select { |signal, total| total == top }.keys
    leaders.size == 1 ? leaders.first : "cross"
  end

  def size_of(text)
    return "l" if text.length > 700
    return "m" if text.length > 200

    "s"
  end

  def scope_paths(text)
    paths = text.scan(ROOTED_PATH) + text.scan(REL_PATH) + text.scan(FILE_PATH)
    paths.map(&:strip).uniq.sort
  end

  # The first runnable command the item names, verbatim: prose backticks
  # first, then the item's fenced code, one command per fence line. A span
  # counts when the prose asks for a command run, or when the span is itself a
  # full invocation on a named checkout ("cd RAILS/bsdports && bin/ci").
  def first_command(item)
    spans = item[:prose].flat_map { |line| line.scan(/`([^`\n]+)`/).flatten }
    spans += item[:code].reject(&:empty?)
    hint = item[:prose].join(" ").match?(Store::EXEC_HINT)
    spans.find { |span| runnable?(span) && (hint || span.match?(/\Acd\s/)) }
  end

  def runnable?(span)
    stripped, chained = without_invocation_prefix(span)
    words = stripped.split
    return false if words.empty?
    return true if command_words?(words, stripped)

    tool_ref?(words.first) && (words.size >= 2 || chained)
  end

  def command_words?(words, stripped)
    words.first.match?(%r{\A(?:ruby|rake|bundle|node|pfctl|swapctl|ssh|git)\z}) &&
      (words.size >= 2 || stripped.include?(":"))
  end

  def tool_ref?(word)
    word.start_with?("bin/", "./") || word.match?(%r{\A(?:MASTER|OPENBSD)/bin/})
  end

  def without_invocation_prefix(span)
    stripped = span.sub(/\A\$/, "")
    # A cd or environment prefix makes the span an invocation written for a
    # checkout, so a bare "bin/ci" inside it is a command, not a named path.
    chained = span.match?(%r{\A(?:cd\s|[A-Z_][A-Z0-9_]*=)})
    loop do
      candidate = stripped.sub(%r{\A(?:cd\s+\S+\s*&&\s+|[A-Z_][A-Z0-9_]*=(?:"[^"]*"|\S+)\s+)}, "")
      return [stripped, chained] if candidate == stripped

      chained = true
      stripped = candidate
    end
  end

  def note_for(item:, command:, kind:)
    return if command
    return "pub5 is gated on the operator's freeze condition, not on one command" if item[:plan]
    return "operator-owned action; the acceptance is the operator's decision" if kind == "operator-only"

    "no runnable command named in the item text"
  end

  def assign_ids!(entries)
    used = {}
    entries.each { |row| row[:id] = slug_for(row[:text], used) }
    entries
  end

  def slug_for(text, used)
    base = text.downcase.scan(/[a-z0-9]+/).first(8).join("-")[0, 80]
    base = "item" if base.empty?
    return base unless used.key?(base)

    digest = Digest::SHA1.hexdigest(text)[0, 6]
    serial = 1
    loop do
      candidate = "#{base}-#{digest}#{serial > 1 ? "-#{serial}" : ""}"
      return candidate unless used.key?(candidate)

      serial += 1
    end
  end
end

module Backlog
  # Closed mapping from explicit acceptance commands to the existing
  # TaskContract proof vocabulary. An unknown command is not guessed.
  module ProofMap
    VERSION = 2
    module_function

    # Normalize only known shell prefixes. This is not a shell parser: an
    # unfamiliar wrapper stays unmapped and therefore cannot authorize intake.
    def normalize_command(value)
      command = value.to_s.strip.sub(/\A\$\s*/, "")
      loop do
        normalized = command
          .sub(/\Acd\s+(?:"[^"]+"|'[^']+'|\S+)\s*&&\s*/, "")
          .sub(/\A[A-Z_][A-Z0-9_]*=(?:"[^"]*"|'[^']*'|\S+)\s+/, "")
          .sub(/\Abundle exec\s+/, "")
        break if normalized == command

        command = normalized.lstrip
      end
      command
    end

    def types_for(row = nil, done_when: nil)
      value = done_when || (row && (row[:done_when] || row["done_when"]))
      command = normalize_command(value)
      return [] if command.empty?

      types = case command
              when /\Arake test(?::batch)?(?:\s|\z)/i,
                   /\Arake check test(?:\s|\z)/i,
                   /\Aruby\s+(?:MASTER|RAILS|OPENBSD|STUDIO)\/test\/run_all\.rb(?:\s|\z)/i,
                   /\Aruby\s+test\/run_all\.rb(?:\s|\z)/i,
                   /\A(?:MASTER\/)?bin\/ci(?:\s|\z)/i
                ["full_suite"]
              when /\Arake test:[a-z0-9_:.-]+(?:\s|\z)/i,
                   /\Aruby\s+(?:-[^\s]+\s+)*(?:test|spec)\/.*\.rb(?:\s|\z)/i,
                   /\Aruby\s+(?:MASTER|RAILS|OPENBSD|STUDIO)\/test\/(?:test_.*|.*_test)\.rb(?:\s|\z)/i,
                   /\Arspec(?:\s|\z)/i,
                   %r{\A(?:MASTER/)?bin/operator test(?:\s|\z)}i
                ["focused_tests"]
              when /\Arake audit(?:\s|\z)/i,
                   /\Arake lint(?::[a-z0-9_:.-]+)?(?:\s|\z)/i,
                   /\A(?:MASTER\/)?bin\/check(?:\s|\z)/i,
                   %r{\A(?:MASTER/)?bin/operator check(?:\s|\z)}i,
                   /\Aruby\s+(?:MASTER\/)?checks\/runner\.rb(?:\s|\z)/i
                ["law_assessment"]
              when %r{\A(?:MASTER/)?bin/operator (?:visual )?sweep(?:\s|\z)}i,
                   %r{\A(?:MASTER/)?bin/operator visual review(?:\s|\z)}i
                ["rendered_evidence"]
              when %r{\A(?:MASTER/)?bin/operator accessibility(?:\s|\z)}i
                ["accessibility_review"]
              when /\Apfctl\s/i,
                   /\Aswapctl\s/i
                ["runtime_evidence"]
              else
                []
              end

      allowed = Master::Fix::TaskContract.template.fetch("proof_types").map(&:to_s)
      unknown = types - allowed
      raise ArgumentError, "proof map names unknown TaskContract types: #{unknown.join(", ")}" unless unknown.empty?

      types.freeze
    end

    def valid_types?(values)
      types = Array(values).map(&:to_s)
      !types.empty? && types.uniq == types &&
        (types - Master::Fix::TaskContract.template.fetch("proof_types").map(&:to_s)).empty?
    end

    EXECUTION_ENV = %w[MASTER_TEST_START_MARKERS MASTER_TEST_JOBS MASTER_TEST_PROGRESS_EVERY].freeze
    PROOF_TIMEOUTS = {
      "full_suite" => 1800,
      "focused_tests" => 900,
      "law_assessment" => 900,
      "rendered_evidence" => 1800,
      "accessibility_review" => 1800,
      "runtime_evidence" => 120,
    }.freeze

    # Produce an argv-only command spec for an acceptance command we own.
    # A nil result means the item must stay out of unattended intake.
    def execution_spec(value, tree:, repo_root:)
      acceptance_command = value.to_s
      raw = acceptance_command.strip.sub(/\A\$\s*/, "")
      return if raw.empty?

      repository = File.realpath(repo_root)
      working_directory = nil
      if (match = raw.match(/\Acd\s+(.+?)\s*&&\s*(.+)\z/))
        directory = Shellwords.shellsplit(match[1])
        return unless directory.one?

        working_directory = safe_directory(repository, directory.first)
        return unless working_directory

        raw = match[2]
      end

      environment = {}
      loop do
        match = raw.match(/\A([A-Z_][A-Z0-9_]*)=(?:"([^"]*)"|'([^']*)'|(\S+))\s+(.+)\z/)
        break unless match

        key = match[1]
        env_value = match[2] || match[3] || match[4]
        return unless EXECUTION_ENV.include?(key)
        return unless env_value.match?(/\A\d+\z/)
        return if key == "MASTER_TEST_JOBS" && env_value.to_i < 1
        return if key == "MASTER_TEST_START_MARKERS" && !%w[0 1].include?(env_value)

        environment[key] = env_value
        raw = match[5]
      end

      raw = raw.sub(/\Abundle exec\s+/, "")
      argv = Shellwords.shellsplit(raw)
      return if argv.empty? || argv.any? { |token| token.match?(/[;&|<>]/) }

      proof_types = types_for(done_when: acceptance_command)
      return unless proof_types.one?
      proof_type = proof_types.first
      return unless PROOF_TIMEOUTS.key?(proof_type)

      if working_directory.nil?
        root_relative = argv.any? { |token| token.match?(/\A(?:MASTER|RAILS|OPENBSD|STUDIO|BIZ)\//) }
        working_directory = if root_relative
                              repository
                            else
                              safe_directory(repository, tree.to_s)
                            end
      end
      return unless working_directory

      launcher, command_argv = executable_argv(
        argv, proof_type:, repository:, working_directory:
      )
      return unless launcher && command_argv

      {
        proof_type:,
        launcher:,
        argv: command_argv,
        cwd: working_directory,
        cwd_relative: working_directory == repository ? "." : working_directory.delete_prefix("#{repository}/"),
        env: environment.freeze,
        command_digest: Digest::SHA256.hexdigest(acceptance_command),
        timeout: PROOF_TIMEOUTS.fetch(proof_type),
      }.freeze
    rescue ArgumentError, SystemCallError
      nil
    end

    # Every component is lstat-checked. Symlinked parents and hard-linked
    # source files are not valid unattended scopes.
    def safe_scope_path?(relative, repo_root:)
      repository = File.realpath(repo_root)
      absolute = File.expand_path(relative.to_s, repository)
      return false unless absolute.start_with?(repository + File::SEPARATOR)

      components = absolute.delete_prefix(repository + File::SEPARATOR).split(File::SEPARATOR)
      return false if components.empty? || components.any? { |part| part.empty? || part == "." || part == ".." }

      cursor = repository
      components.each_with_index do |component, index|
        cursor = File.join(cursor, component)
        stat = File.lstat(cursor)
        return false if stat.symlink?
        if index < components.length - 1 || stat.directory?
          return false unless stat.directory?
        else
          return false unless stat.file? && stat.nlink == 1
        end
      end
      true
    rescue ArgumentError, SystemCallError
      false
    end

    def safe_directory(repository, relative)
      candidate = File.expand_path(relative.to_s, repository)
      return unless candidate == repository || candidate.start_with?(repository + File::SEPARATOR)
      return repository if candidate == repository

      cursor = repository
      candidate.delete_prefix(repository + File::SEPARATOR).split(File::SEPARATOR).each do |component|
        return if component.empty? || component == "." || component == ".."

        cursor = File.join(cursor, component)
        stat = File.lstat(cursor)
        return if stat.symlink? || !stat.directory?
      end
      cursor
    rescue ArgumentError, SystemCallError
      nil
    end

    def safe_file(repository, working_directory, relative)
      absolute = File.expand_path(relative.to_s, working_directory)
      return unless absolute.start_with?(repository + File::SEPARATOR)

      components = absolute.delete_prefix(repository + File::SEPARATOR).split(File::SEPARATOR)
      return if components.empty? || components.any? { |part| part.empty? || part == "." || part == ".." }

      cursor = repository
      components.each_with_index do |component, index|
        cursor = File.join(cursor, component)
        stat = File.lstat(cursor)
        return if stat.symlink?
        if index < components.length - 1
          return unless stat.directory?
        else
          return unless stat.file? && stat.nlink == 1
        end
      end
      cursor
    rescue ArgumentError, SystemCallError
      nil
    end

    def executable_argv(argv, proof_type:, repository:, working_directory:)
      command = argv.first.to_s
      args = argv.drop(1)

      case command
      when "rake"
        allowed = case proof_type
                  when "full_suite"
                    args == ["test"] || args == ["test:batch"] || args == ["check", "test"]
                  when "focused_tests"
                    args.size == 1 && args.first.match?(/\Atest:[a-z0-9_:.-]+\z/i)
                  when "law_assessment"
                    args == ["audit"] || args == ["lint"] ||
                      (args.size == 1 && args.first.match?(/\Alint:[a-z0-9_:.-]+\z/i))
                  else
                    false
                  end
        return unless allowed
        [:bundle, ["rake", *args]]
      when "ruby"
        options = []
        index = 0
        while index < args.length
          token = args[index]
          if token == "-I"
            return unless args[index + 1] && args[index + 1].match?(/\A[\w.\-:\/]+\z/)
            options.concat(["-I", args[index + 1]])
            index += 2
          elsif token.start_with?("-I") && token.length > 2 && token.match?(/\A-I[\w.\-:\/]+\z/)
            options << token
            index += 1
          else
            break
          end
        end
        script = args[index]
        return unless script
        script_path = safe_file(repository, working_directory, script)
        return unless script_path
        tail = args.drop(index + 1)
        relative = script_path.delete_prefix(repository + File::SEPARATOR)

        allowed = case proof_type
                  when "full_suite"
                    relative.match?(%r{\A(?:MASTER|RAILS|OPENBSD|STUDIO)/test/run_all\.rb\z}) ||
                      relative == "test/run_all.rb"
                  when "focused_tests"
                    relative.match?(%r{\A(?:MASTER|RAILS|OPENBSD|STUDIO)/test/(?:test_.*|.*_test)\.rb\z}) ||
                      relative.match?(%r{\A(?:MASTER|RAILS|OPENBSD|STUDIO)/spec/.*_spec\.rb\z}) ||
                      relative.match?(%r{\Atest/(?:test_.*|.*_test)\.rb\z}) ||
                      relative.match?(%r{\Aspec/.*_spec\.rb\z})
                  when "law_assessment"
                    relative == "MASTER/checks/runner.rb" && tail.include?("--scan-only")
                  else
                    false
                  end
        return unless allowed
        [:ruby_bundle, [*options, script_path, *tail]]
      when "rspec"
        return unless proof_type == "focused_tests" && args.any?
        files = args.map { |path| safe_file(repository, working_directory, path) }
        return if files.any?(&:nil?)
        return unless args.all? { |path| path.match?(%r{\Aspec/.*_spec\.rb\z}) }
        [:bundle, ["rspec", *files]]
      when "bin/operator", "MASTER/bin/operator"
        operator = if command.start_with?("MASTER/")
                     safe_file(repository, repository, command)
                   else
                     safe_file(repository, working_directory, command)
                   end
        return unless operator
        valid = case args.first
                when "test"
                  proof_type == "focused_tests"
                when "check"
                  proof_type == "law_assessment" && (args.include?("--scan-only") || args.include?("--no-autofix"))
                when "visual"
                  proof_type == "rendered_evidence" && %w[sweep review].include?(args[1])
                when "accessibility"
                  proof_type == "accessibility_review"
                else
                  false
                end
        return unless valid
        [:ruby_bundle, [operator, *args]]
      when "bin/check", "MASTER/bin/check"
        return unless proof_type == "law_assessment"
        script = command.start_with?("MASTER/") ? safe_file(repository, repository, command) :
                                                  safe_file(repository, working_directory, command)
        return unless script
        [:ruby_bundle, [script, *args]]
      when "bin/ci", "MASTER/bin/ci"
        return unless proof_type == "full_suite"
        script = command.start_with?("MASTER/") ? safe_file(repository, repository, command) :
                                                  safe_file(repository, working_directory, command)
        return unless script && File.executable?(script)
        [:direct, [script, *args]]
      when "pfctl"
        return unless proof_type == "runtime_evidence" && RUBY_PLATFORM.match?(/openbsd/i)
        return unless args == ["-nf", "/etc/pf.conf"]
        [:direct, [command, *args]]
      when "swapctl"
        return unless proof_type == "runtime_evidence" && RUBY_PLATFORM.match?(/openbsd/i)
        return unless args == ["-l"]
        [:direct, [command, *args]]
      else
        nil
      end
    end
  end

  # A deliberately narrow bridge from the generated register to the existing
  # durable Mission/TaskSteward lifecycle. It never edits TODO.md or treats a
  # guessed classification as permission.
  class Executor
    READY_KINDS = %w[mechanical].freeze
    OWNED_TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ].freeze
    RECEIPT_PATH = ".master/backlog-executor.jsonl"

    def initialize(root: Master::ROOT, repo_root: Master::REPO_ROOT, mission_class: nil)
      require_relative "../lib/fix/mission" unless defined?(Master::Fix::Mission)
      @root = File.expand_path(root)
      @repo_root = File.realpath(repo_root)
      @mission_class = mission_class || Master::Fix::Mission
    end

    def enqueue_next!(model: nil, effort: "medium")
      current = @mission_class.current(root: @root)
      state = current && current["state"].to_s
      return :busy if %w[running waiting].include?(state)
      return :blocked if %w[blocked failed].include?(state)
      if current && current["origin"].to_s == "backlog" && state == "completed"
        return :blocked unless record_completion!(record: current)
      end

      entries = Backlog.generate
      receipts = completed_receipts
      item = entries.find do |row|
        eligible?(row) && !receipts.include?(item_digest(row))
      end
      return :idle unless item

      scope = item.fetch(:scope_paths)
      proof_types = ProofMap.types_for(item)
      goal = [
        "Complete exactly this root TODO item, using MASTER's existing /fix pipeline.",
        "Backlog item: #{item.fetch(:id)}",
        "Task: #{item.fetch(:text)}",
        "Owned tree: #{item.fetch(:tree)}",
        "Exact repository-relative scope: #{scope.join(', ')}",
        "Acceptance command from the register: #{item[:done_when]}",
        "Required TaskContract proof types (closed proof-map v#{ProofMap::VERSION}): #{proof_types.join(", ")}. Unknown or absent mappings are not auto-queued.",
        "Do not edit the TODO checkbox. The executor records work only from a durable completed Mission with a delivery summary and no pending repository writes.",
        "Commit each coherent, verified slice and push directly to the existing main branch when the repository-delivery policy authorizes that remote action; do not create PRs, branches, worktrees or GitHub Actions. Stage only task-owned paths after checking git status and preserving unrelated changes.",
        "If the external-publication gate, GitHub authentication or the remote blocks a push, preserve the local commit and report DELIVERY_FAILED; never bypass the gate or claim a push succeeded.",
        "Do not deploy, spend money, contact people, alter production data, or cross a human/operator gate.",
        "If the task requires a product decision, external credential, human approval, or unavailable runtime, block with the exact reason.",
      ].join("\n")
      new_paths = scope.filter_map do |relative|
        absolute = File.expand_path(relative, @repo_root)
        next if absolute == @repo_root || !absolute.start_with?(@repo_root + File::SEPARATOR)
        next if File.exist?(absolute) || File.symlink?(absolute)

        { "path" => relative, "reason" => "Exact path explicitly named by root TODO item #{item.fetch(:id)}." }
      end
      plan = JSON.generate(
        "executor" => "root_todo",
        "item_id" => item.fetch(:id),
        "item_digest" => item_digest(item),
        "source_digest" => Digest::SHA256.file(Backlog::SOURCE).hexdigest,
        "scope_paths" => scope,
        "tree" => item.fetch(:tree),
        "new_paths" => new_paths,
        "done_when" => item[:done_when],
        "proof_map_version" => ProofMap::VERSION,
        "proof_types" => proof_types,
      )
      mission = @mission_class.new(root: @root).ensure_queued!(
        goal:, scope: @root, model:, effort:, plan:,
        origin: "backlog", auto_continue: true, mode: "repair",
        intent: :functional_change,
      )
      return :blocked if mission.respond_to?(:record) && mission.record&.fetch("state", nil) == "blocked"

      :queued
    end

    # Only a terminal Mission with delivery stage, a non-empty summary and
    # durable terminal delivery evidence can close an executor item. No checkbox writes.
    def record_completion!(record: @mission_class.current(root: @root))
      return false unless record && record["origin"].to_s == "backlog"
      return false unless record["state"].to_s == "completed" && record["stage"].to_s == "deliver"
      return false if record["summary"].to_s.strip.empty?
      return false unless record["repository_writes"].to_h.empty?

      plan = JSON.parse(record["plan"].to_s)
      return false unless plan["executor"] == "root_todo" && plan["item_id"] && plan["item_digest"]
      return false unless plan["proof_map_version"] == ProofMap::VERSION
      return false unless ProofMap.valid_types?(plan["proof_types"])
      proof = record["proof"].is_a?(Hash) ? record["proof"] : {}
      return false unless proof["proof_map_version"] == plan["proof_map_version"]
      return false unless Array(proof["required_proof_types"]).map(&:to_s) == Array(plan["proof_types"]).map(&:to_s)
      return false unless proof["kind"] == "fix_pipeline" && proof["status"] == "pass"
      return false unless Array(proof["scope_paths"]).sort == Array(plan["scope_paths"]).map(&:to_s).sort
      return false unless proof["report_digest"].to_s.match?(/\A[0-9a-f]{64}\z/i)
      return false unless proof["proof_summary"].to_s.match?(/fix done.*proof:/i)
      command_evidence = proof["command_evidence"].is_a?(Hash) ? proof["command_evidence"] : {}
      source_item = Backlog.generate.find { |item| item[:id] == plan["item_id"] }
      return false unless source_item && item_digest(source_item) == plan["item_digest"]
      return false unless source_item[:done_when].to_s == plan["done_when"].to_s
      return false unless source_item[:tree].to_s == plan["tree"].to_s
      expected_types = ProofMap.types_for(done_when: source_item[:done_when])
      command_spec = ProofMap.execution_spec(source_item[:done_when], tree: source_item[:tree], repo_root: @repo_root)
      return false unless command_spec && expected_types.one?
      return false unless command_evidence["proof_type"].to_s == expected_types.first
      return false unless Array(plan["proof_types"]).map(&:to_s).include?(command_evidence["proof_type"].to_s)
      return false unless command_evidence["status"] == "pass" && command_evidence["exit_status"] == 0
      return false unless command_evidence["command_digest"].to_s == Digest::SHA256.hexdigest(plan["done_when"].to_s)
      return false unless command_evidence["command_digest"] == command_spec.fetch(:command_digest)
      return false unless command_evidence["output_digest"].to_s.match?(/\A[0-9a-f]{64}\z/i)
      return false unless command_evidence["output_bytes"].is_a?(Integer) && command_evidence["output_bytes"] >= 0
      return false unless command_evidence["duration_ms"].is_a?(Integer) && command_evidence["duration_ms"] >= 0
      cwd = command_evidence["cwd"].to_s
      return false if cwd.empty? || Pathname.new(cwd).absolute? || cwd.split("/").include?("..")
      return false unless cwd == command_spec.fetch(:cwd_relative)
      pushes = Array(record["repository_pushes"])
      return false if pushes.empty?
      return false unless pushes.all? do |push|
        push.is_a?(Hash) && push["remote"] == "origin" && push["branch"] == "main" &&
          push["commit"].to_s.match?(/\A[0-9a-f]{40}\z/i)
      end
      return true if completed_receipts.include?(plan["item_digest"])

      FileUtils.mkdir_p(File.join(@root, ".master"))
      path = File.join(@root, RECEIPT_PATH)
      row = {
        "item_id" => plan.fetch("item_id"),
        "item_digest" => plan.fetch("item_digest"),
        "mission_id" => record.fetch("id"),
        "completed_at" => record.fetch("finished_at"),
        "summary" => record.fetch("summary"),
        "artifacts" => Array(record["artifacts"]),
        "proof_status" => "verified_fix_pipeline_acceptance_and_origin_main",
        "proof" => proof,
        "repository_pushes" => pushes,
        "evidence" => {
          "mission_state" => record.fetch("state"),
          "mission_stage" => record.fetch("stage"),
          "summary" => record.fetch("summary"),
          "pending_repository_writes" => 0,
        },
      }
      File.open(path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
        file.flock(File::LOCK_EX)
        file.puts(JSON.generate(row))
        file.flush
        file.fsync
      end
      true
    rescue JSON::ParserError, KeyError, SystemCallError
      false
    end

    private

    def eligible?(row)
      tree = row[:tree].to_s
      return false unless OWNED_TREES.include?(tree)
      return false unless READY_KINDS.include?(row[:kind].to_s)
      return false unless ProofMap.valid_types?(ProofMap.types_for(row))
      return false unless ProofMap.execution_spec(
        row[:done_when], tree:, repo_root: @repo_root
      )
      paths = Array(row[:scope_paths]).map(&:to_s).uniq
      return false if paths.empty?
      return false unless paths.all? { |path| path.start_with?("#{tree}/") }
      return false if paths.any? { |path| ["*", "?", "{", "}", "[", "]"].any? { |token| path.include?(token) } || path.split("/").include?("..") }
      return false unless paths.all? { |path| safe_scope_path?(path) }

      true
    end

    # Every path component is checked with lstat. A final-file-only symlink
    # check permits an in-repository symlinked parent to redirect a repair,
    # and File.realpath alone does not reject hard-linked source files.
    def safe_scope_path?(relative)
      ProofMap.safe_scope_path?(relative, repo_root: @repo_root)
    end

    def item_digest(row)
      Digest::SHA256.hexdigest([row.fetch(:id), row.fetch(:text), *Array(row[:scope_paths]).sort].join("\0"))
    end

    def completed_receipts
      path = File.join(@root, RECEIPT_PATH)
      return [] unless File.file?(path)

      File.foreach(path).filter_map do |line|
        row = JSON.parse(line)
        row["item_digest"] if row["proof_status"] == "verified_fix_pipeline_acceptance_and_origin_main"
      rescue JSON::ParserError
        nil
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  run = Backlog::Store.parse_cli(ARGV)
  if run[:check]
    exit(Backlog::Store.check(source: run[:source], out: run[:out]))
  else
    exit(Backlog::Store.write(source: run[:source], out: run[:out], refresh: run[:refresh]))
  end
end
