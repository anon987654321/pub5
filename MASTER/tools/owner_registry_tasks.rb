# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"
require "shellwords"
require "yaml"
require "set"
require_relative "../lib/boot/paths"
require_relative "../lib/fix/constants"
require_relative "../lib/ground/failure_taxonomy"
require_relative "../lib/fix/task_contract"
require_relative "../lib/fix/adaptive_journey"

# Explicit, proof-bearing tasks live on existing owner records. This reader
# does not create a second backlog, parse Markdown, infer paths or invent tests.
# Only a row with an explicit agent_task contract enters unattended intake.
module Backlog
  MASTER_ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("..", MASTER_ROOT)

  REGISTRY_SOURCES = {
    "MASTER/convergence.yml" => "workstreams",
    "MASTER/data/gaps.yml" => "gaps",
    "MASTER/data/law/ux_refinements.yml" => "refinements",
    "MASTER/data/operator_seams.yml" => "seams",
    "RAILS/refinements.yml" => "items",
  }.freeze

  TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ].freeze
  KINDS = %w[mechanical].freeze
  SIZES = %w[s m l].freeze

  module_function

  def generate
    REGISTRY_SOURCES.flat_map do |source, collection|
      path = File.join(REPO_ROOT, source)
      next [] unless File.file?(path)

      data = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
      Array(data.fetch(collection, [])).filter_map do |row|
        task = row["agent_task"]
        next unless task
        state = (row["state"] || row["status"]).to_s
        next if %w[landed satisfied rejected blocked operator evidence].include?(state)

        entry(source:, row:, task:)
      end
    end
  end

  def entry(source:, row:, task:)
    id = row.fetch("id").to_s
    text = (row["title"] || row["name"] || row["item"] || row["claim"]).to_s.strip
    tree = task.fetch("tree").to_s
    kind = task.fetch("kind").to_s
    size = task.fetch("size").to_s
    scope_paths = Array(task.fetch("scope_paths")).map(&:to_s)
    done_when = task.fetch("done_when").to_s.strip

    raise ArgumentError, "#{source}##{id} has an empty agent-task id or title" if id.empty? || text.empty?
    raise ArgumentError, "#{source}##{id} names an unowned tree #{tree.inspect}" unless TREES.include?(tree)
    raise ArgumentError, "#{source}##{id} names an unsupported task kind #{kind.inspect}" unless KINDS.include?(kind)
    raise ArgumentError, "#{source}##{id} names an unknown task size #{size.inspect}" unless SIZES.include?(size)
    raise ArgumentError, "#{source}##{id} needs exact non-empty scope_paths" if scope_paths.empty?
    raise ArgumentError, "#{source}##{id} scope crosses its owning tree" unless scope_paths.all? { |path| path.start_with?("#{tree}/") }
    raise ArgumentError, "#{source}##{id} needs an explicit allowlisted acceptance command" if done_when.empty?

    registry_digest = Digest::SHA256.hexdigest(YAML.dump("source" => source, "row" => row))
    {
      id:,
      text:,
      section: source,
      tree:,
      kind:,
      size:,
      scope_paths: scope_paths.uniq.sort,
      done_when:,
      done_when_note: nil,
      dependencies: Array(task["dependencies"]).map(&:to_s),
      registry_source: source,
      registry_digest:,
    }
  end

  def registry_digest(row)
    row[:registry_digest] || Digest::SHA256.hexdigest(YAML.dump(row))
  end

  def item_digest(row)
    Digest::SHA256.hexdigest([
      row.fetch(:id), row.fetch(:text), row.fetch(:tree), row.fetch(:kind),
      row.fetch(:done_when), registry_digest(row),
      *Array(row.fetch(:scope_paths)).sort,
    ].join("\0"))
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
      relative = relative.to_s
      absolute = File.expand_path(relative, repository)
      return false unless absolute.start_with?(repository + File::SEPARATOR)

      canonical = absolute.delete_prefix(repository + File::SEPARATOR)
      return false unless canonical == relative

      components = canonical.split(File::SEPARATOR)
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

  # A deliberately narrow bridge from explicit owner-registry tasks to the
  # existing durable Mission/TaskSteward lifecycle. No prose classification or
  # inferred acceptance command can authorize unattended work.
  class Executor
    READY_KINDS = %w[mechanical].freeze
    OWNED_TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ].freeze
    RECEIPT_PATH = ".master/backlog-executor.jsonl"
    MISSION_OBJECTIVE = "deployment-first: production release, then repository-wide repair, then creative work".freeze

    def initialize(root: Master::ROOT, repo_root: Master::REPO_ROOT, mission_class: nil)
      require_relative "../lib/fix/mission" unless defined?(Master::Fix::Mission)
      @root = File.expand_path(root)
      @repo_root = File.realpath(repo_root)
      @mission_class = mission_class || Master::Fix::Mission
    end

    def enqueue_next!(model: nil, effort: "medium")
      current = @mission_class.current(root: @root)
      state = current && current["state"].to_s
      origin = current && current["origin"].to_s
      return :busy if state == "running"

      if origin == "backlog" && state == "waiting"
        return :busy if due_mission?(current)

        return :delivery_failed unless park_current!(record: current)
      elsif origin == "backlog" && %w[blocked failed].include?(state)
        return :delivery_failed unless park_current!(record: current)
      elsif state == "waiting"
        return :busy
      elsif %w[blocked failed].include?(state)
        return :blocked
      end

      if current && origin == "backlog" && state == "completed"
        unless record_completion!(record: current)
          return :delivery_failed unless park_unverified_completion!(record: current)
        end
      end

      entries = Backlog.generate
      receipts = completed_receipts
      parked = latest_parked_tasks
      candidates = entries.select do |row|
        eligible?(row) && !receipts.include?(item_digest(row)) && !parked_task?(row, parked)
      end
      return :idle if candidates.empty?

      item, decision = select_next(candidates, completed_receipts: receipts)
      return :idle unless item

      scope = item.fetch(:scope_paths)
      proof_types = ProofMap.types_for(item)
      journey = {
        "route_id" => decision.route.id,
        "objective" => MISSION_OBJECTIVE,
        "phase" => mission_phase(item),
        "tree" => item.fetch(:tree),
        "priority" => decision.route.priority,
        "score" => decision.score,
        "reason" => decision.reason,
        "exploration" => decision.exploration,
        "alternatives" => decision.alternatives.map do |row|
          { "id" => row.fetch(:id), "score" => row.fetch(:score), "priority" => row.fetch(:priority) }
        end,
      }
      goal = [
        "Complete exactly this owner-registry task, using MASTER's existing /fix pipeline.",
        "Owner-registry item: #{item.fetch(:id)}",
        "Task: #{item.fetch(:text)}",
        "Owned tree: #{item.fetch(:tree)}",
        "Exact repository-relative scope: #{scope.join(', ')}",
        "Acceptance command from the owning registry: #{item[:done_when]}",
        "Adaptive journey: phase=#{journey.fetch("phase")} priority=#{journey.fetch("priority")} score=#{journey.fetch("score")} reason=#{journey.fetch("reason")}. Alternatives are bounded to the same mission-priority band.",
        "Required TaskContract proof types (closed proof-map v#{ProofMap::VERSION}): #{proof_types.join(", ")}. Unknown or absent mappings are not auto-queued.",
        "Do not edit an owner state on assumption. The executor records completion only from a durable Mission with a delivery summary and no pending repository writes; the owner retains its proof state until its declared evidence is accepted.",
        "Commit each coherent, verified slice and push directly to the existing main branch when the repository-delivery policy authorizes that remote action; do not create PRs, branches, worktrees or GitHub Actions. Stage only task-owned paths after checking git status and preserving unrelated changes.",
        "If the external-publication gate, GitHub authentication or the remote blocks a push, preserve the local commit and report DELIVERY_FAILED; never bypass the gate or claim a push succeeded.",
        "Do not deploy, spend money, contact people, alter production data, or cross a human/operator gate.",
        "If the task requires a product decision, external credential, human approval, or unavailable runtime, block with the exact reason.",
      ].join("\n")
      new_paths = scope.filter_map do |relative|
        absolute = File.expand_path(relative, @repo_root)
        next if absolute == @repo_root || !absolute.start_with?(@repo_root + File::SEPARATOR)
        next if File.exist?(absolute) || File.symlink?(absolute)

        { "path" => relative, "reason" => "Exact path explicitly declared by #{item.fetch(:registry_source)} item #{item.fetch(:id)}." }
      end
      plan = JSON.generate(
        "executor" => "owner_registry",
        "item_id" => item.fetch(:id),
        "item_digest" => item_digest(item),
        "registry_source" => item[:registry_source].to_s,
        "registry_digest" => Backlog.registry_digest(item),
        "scope_paths" => scope,
        "tree" => item.fetch(:tree),
        "new_paths" => new_paths,
        "done_when" => item[:done_when],
        "proof_map_version" => ProofMap::VERSION,
        "proof_types" => proof_types,
        "journey" => journey,
      )
      mission = @mission_class.new(root: @root).ensure_queued!(
        goal:, scope: @root, model:, effort:, plan:,
        origin: "backlog", auto_continue: true, mode: "repair",
        intent: :functional_change, resume_blocked: resume_requested?(item, parked),
      )
      return :blocked if mission.respond_to?(:record) && mission.record&.fetch("state", nil) == "blocked"

      :queued
    end

    # Read-only overview of owner-registry intake and durable task outcomes.
    # Raw prompts and exception text are intentionally not exposed here.
    def status
      current = @mission_class.current(root: @root)
      entries = Backlog.generate
      completed = completed_receipts.to_set
      parked = latest_parked_tasks
      eligible = entries.select { |item| eligible?(item) }
      ready = eligible.count do |item|
        digest = item_digest(item)
        !completed.include?(digest) && !parked_task?(item, parked)
      end
      parked_rows = parked.filter_map do |digest, receipt|
        next unless receipt["record_type"] == "parked_task"

        {
          "item_id" => receipt["item_id"].to_s,
          "failure_category" => receipt["failure_category"].to_s,
          "mission_state" => receipt["mission_state"].to_s,
          "requires_operator" => receipt["requires_operator"] == true,
          "retry_at" => receipt["retry_at"],
          "item_current" => entries.any? { |item| item_digest(item) == digest },
        }
      end
      {
        "current_mission" => current&.slice("id", "state", "origin", "auto_continue",
                                            "attempt_count", "retry_count", "next_wake_at"),
        "owner_registry_items" => entries.size,
        "eligible_items" => eligible.size,
        "completed_items" => completed.size,
        "ready_items" => ready,
        "parked_items" => parked_rows.size,
        "parked" => parked_rows.sort_by { |row| row.fetch("item_id") },
      }
    end

    # Park an unsuccessful backlog item in the executor's existing durable
    # receipt stream. The owner registry remains the task source; this is outcome
    # history, not a second queue.
    def park_current!(record:, result: nil)
      return false unless record && record["origin"].to_s == "backlog"
      return false unless %w[waiting blocked failed].include?(record["state"].to_s)

      plan = JSON.parse(record["plan"].to_s)
      return :stale unless plan["executor"] == "owner_registry"
      source_item = Backlog.generate.find { |item| item[:id].to_s == plan["item_id"].to_s }
      return :stale unless source_item && item_digest(source_item) == plan["item_digest"].to_s
      return true if parked_task_rows.any? { |row| row["mission_id"].to_s == record["id"].to_s }

      paths = Array(plan["scope_paths"]).map(&:to_s)
      scope_digest = scope_digest_for(paths)

      message = record["wake_reason"].to_s
      message = record["error"].to_s if message.empty?
      message = result.message.to_s if message.empty? && result.respond_to?(:message)
      category = Master::Ground::FailureTaxonomy.shared.classify(message)
      retry_at = if record["state"].to_s == "waiting" && %i[transient exhausted].include?(category)
                   value = record["next_wake_at"].to_s
                   value unless value.empty?
                 end
      return false unless append_executor_receipt(
        "record_type" => "parked_task",
        "item_id" => source_item.fetch(:id).to_s,
        "item_digest" => plan.fetch("item_digest").to_s,
        "mission_id" => record.fetch("id").to_s,
        "mission_state" => record.fetch("state").to_s,
        "failure_category" => category.to_s,
        "retry_at" => retry_at,
        "requires_operator" => record["state"].to_s == "blocked" || %i[permanent ambiguous].include?(category),
        "scope_digest" => scope_digest,
        "parked_at" => Time.now.utc.iso8601,
      )
      true
    rescue JSON::ParserError, KeyError
      :stale
    rescue ArgumentError, SystemCallError
      false
    end

    # An explicit operator action can release one parked item. It does not
    # mark the work complete or bypass its original proof command.
    def resume_item!(item_id:)
      item = Backlog.generate.find { |row| row[:id].to_s == item_id.to_s }
      return false unless item && eligible?(item)

      parked = latest_parked_tasks[item_digest(item)]
      return false unless parked && parked["record_type"] == "parked_task"
      return false unless parked["requires_operator"] == true

      append_executor_receipt(
        "record_type" => "resume_task",
        "item_id" => item.fetch(:id).to_s,
        "item_digest" => item_digest(item),
        "resumed_at" => Time.now.utc.iso8601,
      )
      true
    rescue SystemCallError
      false
    end

    # A run may be terminal without satisfying the executor's stronger
    # delivery receipt. Keep that objective visibly unverified and park it
    # for review; never convert it into a completion receipt.
    def park_unverified_completion!(record:)
      return false unless record && record["origin"].to_s == "backlog" && record["state"].to_s == "completed"

      plan = JSON.parse(record["plan"].to_s)
      return :stale unless plan["executor"] == "owner_registry"
      item = Backlog.generate.find { |row| row[:id].to_s == plan["item_id"].to_s }
      return :stale unless item && item_digest(item) == plan["item_digest"].to_s
      return true if parked_task_rows.any? { |row| row["mission_id"].to_s == record["id"].to_s }

      append_executor_receipt(
        "record_type" => "parked_task",
        "item_id" => item.fetch(:id).to_s,
        "item_digest" => plan.fetch("item_digest").to_s,
        "mission_id" => record.fetch("id").to_s,
        "mission_state" => "completed_unverified",
        "failure_category" => "ambiguous",
        "retry_at" => nil,
        "requires_operator" => true,
        "scope_digest" => scope_digest_for(Array(plan["scope_paths"])),
        "parked_at" => Time.now.utc.iso8601,
        "reason_code" => "terminal_delivery_proof_missing",
      )
    rescue JSON::ParserError, KeyError
      :stale
    rescue ArgumentError, SystemCallError
      false
    end

    # Only a terminal Mission with delivery stage, a non-empty summary and
    # durable terminal delivery evidence can close an executor item. No checkbox writes.
    def record_completion!(record: @mission_class.current(root: @root))
      return false unless record && record["origin"].to_s == "backlog"
      return false unless record["state"].to_s == "completed" && record["stage"].to_s == "deliver"
      return false if record["summary"].to_s.strip.empty?
      return false unless record["repository_writes"].to_h.empty?

      plan = JSON.parse(record["plan"].to_s)
      return false unless plan["executor"] == "owner_registry" && plan["item_id"] && plan["item_digest"]
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
      return false unless source_item[:registry_source].to_s == plan["registry_source"].to_s
      return false unless Backlog.registry_digest(source_item) == plan["registry_digest"].to_s
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
      journey = plan["journey"]
      if journey
        return false unless journey.is_a?(Hash)
        return false unless journey["route_id"].to_s == plan["item_digest"].to_s
        return false unless journey["tree"].to_s == source_item[:tree].to_s
        return false unless journey["objective"].to_s == MISSION_OBJECTIVE
        return false unless journey["phase"].to_s == mission_phase(source_item)
        return false unless journey["priority"].is_a?(Numeric) && journey["priority"] == journey_priority(source_item)
        return false unless journey["score"].is_a?(Numeric) && journey["score"].finite? && journey["score"].between?(0.0, 100.0)
        return false unless journey["alternatives"].is_a?(Array) && journey["alternatives"].size <= 5
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
        "journey" => plan["journey"],
        "journey_outcome" => if plan["journey"].is_a?(Hash)
          { "status" => "PASS", "evidence_id" => proof.fetch("report_digest") }
        end,
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

    def due_mission?(record)
      value = record["next_wake_at"].to_s
      return true if value.empty?

      Time.iso8601(value) <= Time.now.utc
    rescue ArgumentError
      true
    end

    def scope_digest_for(paths)
      facts = Array(paths).map(&:to_s).uniq.sort.map do |relative|
        full = File.expand_path(relative, @repo_root)
        return nil unless full.start_with?(@repo_root + File::SEPARATOR)

        if File.file?(full) || File.symlink?(full)
          return nil unless safe_scope_path?(relative)

          [relative, Digest::SHA256.file(full).hexdigest]
        else
          [relative, "missing"]
        end
      end
      Digest::SHA256.hexdigest(JSON.generate(facts))
    rescue ArgumentError, SystemCallError
      nil
    end

    def parked_task_rows
      directory = File.join(@root, ".master")
      directory_stat = File.lstat(directory)
      return [] unless private_receipt_directory?(directory, directory_stat)

      path = File.join(directory, "backlog-executor.jsonl")
      return [] unless File.exist?(path)

      stat = File.lstat(path)
      return [] unless stat.file? && !stat.symlink? && stat.nlink == 1 && (stat.mode & 0o077).zero?

      File.foreach(path).filter_map do |line|
        row = JSON.parse(line)
        next unless row.is_a?(Hash)
        next unless %w[parked_task resume_task].include?(row["record_type"].to_s)
        next unless row["item_digest"].to_s.match?(/\A[0-9a-f]{64}\z/i)

        row
      rescue JSON::ParserError, ArgumentError
        nil
      end
    rescue SystemCallError
      []
    end

    def latest_parked_tasks
      parked_task_rows.each_with_object({}) do |row, latest|
        latest[row.fetch("item_digest")] = row
      end
    end

    def parked_task?(item, parked)
      latest = parked[item_digest(item)]
      return false unless latest && latest["record_type"] == "parked_task"
      return true if latest["requires_operator"] == true

      retry_at = latest["retry_at"].to_s
      unless retry_at.empty?
        return false if Time.iso8601(retry_at) <= Time.now.utc
      end

      current_scope = scope_digest_for(item[:scope_paths])
      return false if current_scope && current_scope != latest["scope_digest"].to_s

      true
    rescue ArgumentError
      true
    end

    def resume_requested?(item, parked)
      parked.dig(item_digest(item), "record_type") == "resume_task"
    end

    # Match MASTER's existing private-state policy: no access for others,
    # owner access retained, and an intentional foreign-group grant preserved.
    # The directory must not be substituted between lstat and mode evaluation.
    def private_receipt_directory?(directory, original_stat)
      return false unless original_stat.directory? && !original_stat.symlink?

      current = File.lstat(directory)
      return false unless current.directory? && !current.symlink? &&
                          current.dev == original_stat.dev && current.ino == original_stat.ino

      mode = current.mode & 0o2777
      return mode == MasterPaths.private_dir_mode(directory, 0o700) if File.owned?(directory)

      group_member = current.gid == Process.egid || Process.groups.include?(current.gid)
      (mode & 0o700) == 0o700 && (mode & 0o007).zero? &&
        (mode & 0o030) == 0o030 && group_member
    rescue ArgumentError, SystemCallError
      false
    end

    def append_executor_receipt(row)
      directory = File.join(@root, ".master")
      FileUtils.mkdir_p(directory, mode: 0o700)
      directory_stat = File.lstat(directory)
      return false unless private_receipt_directory?(directory, directory_stat)

      path = File.join(directory, "backlog-executor.jsonl")
      if File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        return false unless stat.file? && !stat.symlink? && stat.nlink == 1 && (stat.mode & 0o077).zero?
      end

      flags = File::WRONLY | File::CREAT | File::APPEND
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(path, flags, 0o600) do |file|
        file.flock(File::LOCK_EX)
        stat = file.stat
        return false unless stat.file? && stat.nlink == 1 && (stat.mode & 0o077).zero?

        file.puts(JSON.generate(row))
        file.flush
        file.fsync
      end
      true
    end

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
      Backlog.item_digest(row)
    end

    def row_registry_digest(rows)
      rows.map { |row| [row[:registry_source].to_s, Backlog.registry_digest(row)] }
          .sort.flatten.join("\0")
          .then { |value| Digest::SHA256.hexdigest(value) }
    end
    # Route history is reconstructed only from durable completion receipts
    # whose item, current acceptance command, output digest and origin/main push
    # still agree with the live owner-registry task.
    def completed_receipts
      completed_receipt_rows.map { |row| row.fetch("item_digest") }.uniq
    end

    def verified_route_history
      completed_receipt_rows.filter_map do |row|
        journey = row["journey"].is_a?(Hash) ? row["journey"] : {}
        outcome = row["journey_outcome"].is_a?(Hash) ? row["journey_outcome"] : {}
        evidence_id = row.dig("proof", "report_digest").to_s
        next if journey["route_id"].to_s.empty?
        next unless outcome["status"] == "PASS" && outcome["evidence_id"].to_s == evidence_id
        next unless evidence_id.match?(/\A[0-9a-f]{64}\z/i)

        { "route_id" => journey.fetch("route_id"), "status" => "PASS",
          "evidence_id" => evidence_id, "verified" => true }
      end
    end

    def completed_receipt_rows
      path = File.join(@root, RECEIPT_PATH)
      return [] unless File.exist?(path)

      stat = File.lstat(path)
      return [] unless stat.file? && !stat.symlink? && (stat.mode & 0o077).zero?

      File.foreach(path).filter_map do |line|
        row = JSON.parse(line)
        row if valid_completion_receipt?(row)
      rescue JSON::ParserError, KeyError, ArgumentError, SystemCallError
        nil
      end
    rescue SystemCallError
      []
    end

    def valid_completion_receipt?(row)
      return false unless row.is_a?(Hash)
      return false unless row["proof_status"] == "verified_fix_pipeline_acceptance_and_origin_main"
      return false unless row["mission_id"].to_s.match?(/\A[a-zA-Z0-9:_-]{1,200}\z/)
      return false unless row["completed_at"].to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)
      return false unless row.dig("evidence", "mission_state") == "completed"
      return false unless row.dig("evidence", "mission_stage") == "deliver"
      return false unless row.dig("evidence", "pending_repository_writes") == 0
      return false if row["summary"].to_s.strip.empty?

      source_item = Backlog.generate.find { |item| item[:id].to_s == row["item_id"].to_s }
      return false unless source_item && item_digest(source_item) == row["item_digest"].to_s
      return false unless row["item_digest"].to_s.match?(/\A[0-9a-f]{64}\z/i)

      proof = row["proof"].is_a?(Hash) ? row["proof"] : {}
      return false unless proof["kind"] == "fix_pipeline" && proof["status"] == "pass"
      return false unless proof["scope_paths"].is_a?(Array)
      return false unless proof["scope_paths"].map(&:to_s).sort == Array(source_item[:scope_paths]).map(&:to_s).sort
      return false unless proof["report_digest"].to_s.match?(/\A[0-9a-f]{64}\z/i)
      return false unless proof["proof_summary"].to_s.match?(/fix done.*proof:/i)

      required_types = ProofMap.types_for(source_item)
      return false unless ProofMap.valid_types?(required_types)
      return false unless Array(proof["required_proof_types"]).map(&:to_s) == required_types

      command_spec = ProofMap.execution_spec(
        source_item[:done_when], tree: source_item[:tree], repo_root: @repo_root
      )
      return false unless command_spec && required_types.one?
      command = proof["command_evidence"].is_a?(Hash) ? proof["command_evidence"] : {}
      return false unless command["proof_type"].to_s == required_types.first
      return false unless command["status"] == "pass" && command["exit_status"] == 0
      return false unless command["command_digest"].to_s == command_spec.fetch(:command_digest)
      return false unless command["output_digest"].to_s.match?(/\A[0-9a-f]{64}\z/i)
      return false unless command["output_bytes"].is_a?(Integer) && command["output_bytes"] >= 0
      return false unless command["duration_ms"].is_a?(Integer) && command["duration_ms"] >= 0
      return false unless command["cwd"].to_s == command_spec.fetch(:cwd_relative)

      pushes = Array(row["repository_pushes"])
      return false if pushes.empty?
      return false unless pushes.all? do |push|
        push.is_a?(Hash) && push["remote"] == "origin" && push["branch"] == "main" &&
          push["commit"].to_s.match?(/\A[0-9a-f]{40}\z/i)
      end

      journey = row["journey"]
      return true if journey.nil? # Older verified receipts remain valid, but do not train the planner.
      return false unless journey.is_a?(Hash)
      return false unless journey["route_id"].to_s == row["item_digest"].to_s
      return false unless journey["tree"].to_s == source_item[:tree].to_s
      return false unless journey["objective"].to_s == MISSION_OBJECTIVE
      return false unless journey["phase"].to_s == mission_phase(source_item)
      return false unless journey["priority"].is_a?(Numeric) && journey["priority"] == journey_priority(source_item)
      return false unless journey["score"].is_a?(Numeric) && journey["score"].finite? && journey["score"].between?(0.0, 100.0)
      return false unless journey["alternatives"].is_a?(Array) && journey["alternatives"].size <= 5

      outcome = row["journey_outcome"].is_a?(Hash) ? row["journey_outcome"] : {}
      outcome["status"] == "PASS" && outcome["evidence_id"].to_s == proof["report_digest"].to_s
    end

    def select_next(rows, completed_receipts:)
      registry_digest = row_registry_digest(rows)
      evidence = [{
        id: "registries:#{registry_digest}", sha256: registry_digest, verified: true,
        kind: "owner_registry_set",
      }]
      routes = rows.filter_map do |row|
        spec = ProofMap.execution_spec(row[:done_when], tree: row[:tree], repo_root: @repo_root)
        next unless spec

        scope_facts = Array(row[:scope_paths]).map do |relative|
          absolute = File.join(@repo_root, relative)
          [relative, Digest::SHA256.file(absolute).hexdigest]
        end.sort
        scope_digest = Digest::SHA256.hexdigest(JSON.generate(scope_facts))
        route_id = item_digest(row)
        item_evidence = [
          { id: "registry:#{Backlog.registry_digest(row)}", sha256: Backlog.registry_digest(row),
            verified: true, kind: "explicit_owner_registry_task" },
          { id: "item:#{route_id}", sha256: route_id, verified: true, kind: "owner_registry_item" },
          { id: "command:#{spec.fetch(:command_digest)}", sha256: spec.fetch(:command_digest),
            verified: true, kind: "allowlisted_acceptance_command" },
          { id: "scope:#{scope_digest}", sha256: scope_digest, verified: true, kind: "existing_scope_hashes" },
        ]
        evidence.concat(item_evidence)
        {
          id: route_id,
          actions: [row[:text].to_s, row[:section].to_s],
          evidence_ids: ["registries:#{registry_digest}", *item_evidence.map { |item| item.fetch(:id) }],
          impact: journey_impact(row),
          confidence: 0.95,
          priority: journey_priority(row),
          cost: { "s" => 0.25, "m" => 0.45, "l" => 0.8 }.fetch(row[:size].to_s, 0.5),
          risk: { "OPENBSD" => 0.25, "RAILS" => 0.2, "MASTER" => 0.15 }.fetch(row[:tree].to_s, 0.1),
          reversibility: "easy",
          causes: [],
          preserves: ["exact_single_tree_scope", "existing_paths", "operator_gates"],
          dependencies: Array(row[:dependencies]).map(&:to_s),
        }
      rescue SystemCallError, ArgumentError
        nil
      end

      return [nil, nil] if routes.empty?

      planner = Master::Fix::AdaptiveJourney.new(history: verified_route_history)
      decision = planner.choose(
        routes:, verified_evidence: evidence.uniq { |item| item.fetch(:id) },
        objective: MISSION_OBJECTIVE, satisfied_dependencies: completed_receipts, exploration: true
      )
      selected = rows.find { |row| item_digest(row) == decision.route.id }
      [selected, decision]
    end

    def journey_priority(row)
      tree = row[:tree].to_s
      text = "#{row[:section]} #{row[:text]}".downcase
      case
      when tree == "OPENBSD" && text.match?(/deploy|vm23|receipt|restore|recover|pfctl|rehears|runner/)
        1.0
      when tree == "MASTER" && text.match?(/deploy|preflight|release|boot|receipt|installed compatible ruby/)
        0.97
      when tree == "RAILS" && text.match?(/deploy|production|full contracts|app.*ci|migration|acceptance/)
        0.92
      when text.match?(/repository.wide|all.tree|all trees|all four|\/fix/)
        0.88
      when tree == "MASTER" || tree == "RAILS" || tree == "OPENBSD"
        0.78
      when tree == "STUDIO" || tree == "BIZ"
        0.45
      else
        0.6
      end
    end

    def mission_phase(row)
      priority = journey_priority(row)
      return "release_safety" if priority >= 0.97 && row[:tree].to_s == "OPENBSD"
      return "release_preflight" if priority >= 0.97 && row[:tree].to_s == "MASTER"
      return "application_validation" if priority >= 0.9 && row[:tree].to_s == "RAILS"
      return "repository_repair" if priority >= 0.85
      return "creative_acceptance" if %w[STUDIO BIZ].include?(row[:tree].to_s)

      "tree_acceptance"
    end

    def journey_impact(row)
      text = "#{row[:section]} #{row[:text]}".downcase
      return 0.98 if text.match?(/production|restore|recovery|security|critical|deployment/)
      return 0.9 if text.match?(/full|complete|all.tree|repository.wide|acceptance/)

      0.78
    end
  end
end

