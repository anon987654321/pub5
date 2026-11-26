# frozen_string_literal: true

# What MASTER knows, in a form an agent can be handed before every message.
#
# Context is a bounded projection of canonical stores and registries. Do not
# duplicate their current populations or external-agent paths in this file:
# adapters and inventories change, while the authoritative records remain in
# their owning sources.
#
#   ruby MASTER/tools/agent_context.rb                 # the standing context
#   ruby MASTER/tools/agent_context.rb "<prompt>"      # plus what matches it
#   ruby MASTER/tools/agent_context.rb --json          # the same, as data
#   ruby MASTER/tools/agent_context.rb --json --checks # plus the claim-to-check map
#   ruby MASTER/tools/agent_context.rb --json --tree   # plus the tree map
#
# Designed for a UserPromptSubmit hook, so it stays bounded: retrieve the
# relevant Law rows and current check map instead of injecting the full
# catalogue on every turn. The projection carries governing conduct, the
# checks that can block the task and the gaps that remain unmeasured.

require "digest"
require "yaml"
require_relative "../lib/fix/protocol"
require_relative "../lib/operator/capability_manifest"

module Operator
  module AgentContext
    MASTER_DIR = File.expand_path("..", __dir__)
    REPO_ROOT = File.expand_path("..", MASTER_DIR)
    BLOCKING = %i[veto critical error].freeze
    TREE_DEFAULT_DEPTH = 2
    TREE_DEFAULT_MAX_ENTRIES = 2_000
    TREE_SKIP = %w[.git .bundle vendor node_modules tmp log coverage storage .master .constitutional_locks knowledge output sockets pids cache].freeze

    module_function

    # The practice Laws are executable declarations under law/. They provide
    # operator-facing conduct instructions; they do not derive from Soul or form
    # a second normative catalogue.
    def conduct
      load_master
      require File.join(MASTER_DIR, "law", "definition") unless defined?(::Law)
      ::Law.load_all(File.join(MASTER_DIR, "law")) if ::Law.definitions.empty?
      ::Law.definitions.values.select(&:practice).to_h do |rule|
        [rule.id.to_s, rule.practice.to_s.gsub(/\s+/, " ").strip]
      end
    rescue StandardError => e
      { "conduct unavailable" => e.class.to_s }
    end

    # Only the rules that can refuse a write. A list of 242 is a reference; a
    # list of what actually blocks is an instruction.
    def blocking_rules
      load_master
      Master.law_entries(root: MASTER_DIR)
            .select { |rule| BLOCKING.include?(rule["severity"].to_s.to_sym) }
            .filter_map { |rule| rule["id"] }.sort
    end

    def load_master
      $LOAD_PATH.unshift(File.join(MASTER_DIR, "lib")) unless $LOAD_PATH.include?(File.join(MASTER_DIR, "lib"))
      require "master"
    end

    def coverage
      load_master
      Master::Review::Scan::LawRegistryAudit.new(root: MASTER_DIR).call.coverage_line
    rescue StandardError => e
      "Law coverage unavailable (#{e.class})"
    end

    # Memory is matched on the words of the prompt rather than searched
    # semantically: a hook has milliseconds, and an exact-word hit on a lesson
    # filename is a better signal than an embedding at this size.
    def lessons(query)
      return [] unless query

      path = File.join(MASTER_DIR, "data", "recovery", "pub_archive_restore.yml")
      return [] unless File.file?(path)

      words = query.downcase.scan(/[a-z]{4,}/).uniq
      name = File.basename(path, ".yml").tr("_", " ")
      words.any? { |w| name.include?(w) } ? [path] : []
    end

    def shell_contract
      load_master
      Master::AI::OperatorContract.prompt.lines.map { |line| "  #{line.rstrip}" }
    end

    # Canonical context for an external model asked to execute /fix.
    def fix_context(target: REPO_ROOT, full: false)
      load_master
      target = File.expand_path(target, Dir.pwd)
      Master::Fix::Protocol.context(root: REPO_ROOT, target:, full:)
    rescue StandardError => e
      "MASTER /fix context unavailable: #{e.class}: #{e.message}"
    end

    def fix_context_args(argv)
      marker = argv.index("--fix-context")
      return unless marker

      target = REPO_ROOT
      full = false
      argv[(marker + 1)..].to_a.each do |arg|
        case arg
        when "--full"
          full = true
        else
          target = File.expand_path(arg, Dir.pwd) if !arg.start_with?("--") && target == REPO_ROOT
        end
      end
      [target, full]
    end

    def tree_args(argv)
      args = argv.dup
      marker = args.index("--tree")
      return unless marker

      depth = TREE_DEFAULT_DEPTH
      max_entries = TREE_DEFAULT_MAX_ENTRIES
      root = REPO_ROOT

      i = marker + 1
      if args[i] && !args[i].start_with?("--")
        root = File.expand_path(args[i], Dir.pwd)
      end

      args[i..].to_a.each do |arg|
        case arg
        when /\A--depth=(\d+)\z/
          depth = Regexp.last_match(1).to_i
        when /\A--max-entries=(\d+)\z/
          max_entries = Regexp.last_match(1).to_i
        end
      end

      [root, depth.clamp(0, 12), max_entries.clamp(1, 20_000)]
    end

    def render_tree(root: REPO_ROOT, max_depth: TREE_DEFAULT_DEPTH, max_entries: TREE_DEFAULT_MAX_ENTRIES)
      root = File.realpath(root)
      raise "tree root is not a directory: #{root}" unless Dir.exist?(root)

      lines = []
      seen = 0
      truncated = false

      walk = lambda do |dir, indent, depth|
        return if depth > max_depth || truncated

        entries = Dir.children(dir).sort_by do |name|
          path = File.join(dir, name)
          [File.directory?(path) ? 0 : 1, name]
        end

        entries.each do |name|
          break if seen >= max_entries
          next if TREE_SKIP.include?(name)

          path = File.join(dir, name)
          stat = File.lstat(path)
          seen += 1
          suffix = if stat.symlink? then "@"
                   elsif stat.directory? then "/"
                   else ""
                   end
          lines << "#{indent}+-- #{name}#{suffix}"

          if stat.directory? && !stat.symlink?
            if depth < max_depth
              walk.call(path, "#{indent}|   ", depth + 1)
            else
              lines << "#{indent}|   +-- ... (depth limit)"
              seen += 1
            end
          end
        end

        truncated = true if seen >= max_entries
      end

      lines << "#{File.basename(root)}/"
      walk.call(root, "", 0)
      lines << "+-- ... (max entries reached)" if truncated

      header = [
        "source_tree: #{root}",
        "depth: #{max_depth}",
        "entries shown: #{seen}",
        "skips: #{TREE_SKIP.join(", ")}",
      ]
      (header + [""] + lines).join("\n")
    rescue SystemCallError => e
      "source_tree: unavailable: #{e.class}: #{e.message}"
    end

    def source_authority
      load_master
      require File.join(MASTER_DIR, "lib", "soul") unless defined?(Master::Soul)
      Master::Soul.authority_order(root: REPO_ROOT)
    end

    # The Laws every task carries and how their proof aggregates, from
    # data/core_spine.yml. laws.yml stays the owner of each Law's statement.
    def core_spine
      source = "MASTER/data/core_spine.yml"
      path = File.join(MASTER_DIR, "data", "core_spine.yml")
      raise "core spine missing: #{source}" unless File.file?(path)

      load_master
      spine = Master.load_yaml(path)
      ids = Array(spine.fetch("law_ids")).map(&:to_s)
      {
        "source" => source, "law_ids" => ids, "sha256" => Digest::SHA256.hexdigest(ids.join("\n")),
        "proof_policy" => spine.fetch("proof_policy"),
      }
    rescue StandardError => e
      { "source" => source, "status" => "unavailable", "error" => "#{e.class}: #{e.message}" }
    end

    def core_spine_line
      spine = core_spine
      "Core spine (#{spine["source"]}): #{spine.fetch("law_ids") { [spine["error"]] }.join(", ")}"
    end

    def render(query = nil)
      out = authority_lines + conduct_lines + capability_lines
      out.concat(shell_contract)
      matched = lessons(query)
      out << "Lessons matching this prompt: #{matched.map { |p| File.basename(p, '.yml') }.join(', ')}" if matched.any?
      out.join("\n")
    end

    def authority_lines
      authority = source_authority.map { |row| row.fetch("id") }.join(" > ")
      ["Source authority (highest first): #{authority}", "MASTER conduct in force (law/practice.rb):"]
    end

    def conduct_lines
      conduct.map { |name, text| "  #{name}: #{text.to_s.split(/(?<=\.)\s/).first}" } + ["",
        "Rules that can refuse a write (#{blocking_rules.size}): #{blocking_rules.join(', ')}",
        "Coverage: #{coverage}", core_spine_line]
    end

    def capability_lines
      rows = Operator::CapabilityManifest.new(root: REPO_ROOT).call.fetch("capabilities")
      ["Execution capabilities: #{rows.map { |name, row| "#{name}=#{row.fetch("status")}" }.join(", ")}", ""]
    end

    # Project the operational check registry for agents that need to connect a
    # stated claim to the instrument and preconditions that produce it. The
    # runner remains the execution authority; this projection is not evidence
    # that a check ran or passed, and it is not a second registry.
    def claim_check_map
      source = "MASTER/checks/checks.yml"
      path = File.join(MASTER_DIR, "checks", "checks.yml")
      registry = YAML.safe_load_file(path, aliases: false)
      raise "check registry root must be a mapping" unless registry.is_a?(Hash)

      entries = registry.sort.map do |name, row|
        raise "check registry row #{name} must be a mapping" unless row.is_a?(Hash)

        has_class = row.key?("class")
        has_script = row.key?("script")
        raise "check registry row #{name} must declare exactly one instrument" unless has_class ^ has_script

        instrument = if has_script
                       { "kind" => "script", "path" => row.fetch("script") }
                     else
                       { "kind" => "class", "class" => row.fetch("class") }
                     end
        instrument["require"] = row["require"] if row["require"].is_a?(String)

        claim = row["pass"].to_s.strip
        entry = {
          "check" => name.to_s,
          "claim" => claim.empty? ? nil : claim,
          "claim_status" => claim.empty? ? "not_declared" : "declared",
          "instrument" => instrument,
          "needs" => Array(row["needs"]).map(&:to_s),
        }
        entry["covered_by"] = row["covered_by"].to_s if row["covered_by"]
        entry["gap"] = row["gap"] if row["gap"].is_a?(Hash)
        entry
      end

      {
        "schema" => 1,
        "source" => source,
        "execution_command" => "ruby MASTER/checks/runner.rb --all",
        "interpretation" => "Registry claims and instruments only; not evidence of execution or success.",
        "entry_count" => entries.size,
        "entries" => entries,
      }
    rescue StandardError => e
      { "schema" => 1, "source" => source, "status" => "unavailable", "error" => e.class.to_s }
    end

    # The same standing context as #render, as data. The full operational
    # claim-to-check map is opt-in with --checks so routine prompt context stays
    # bounded; --tree adds the rendered source tree under "tree".
    def session_json(tree: false, tree_root: REPO_ROOT, tree_depth: TREE_DEFAULT_DEPTH, tree_max_entries: TREE_DEFAULT_MAX_ENTRIES, checks: false)
      require "json"
      authority_order = source_authority
      payload = {
        "source" => "MASTER/tools/agent_context.rb",
        "authority_order" => authority_order,
        "authority" => authority_order.map { |row| row.fetch("source") },
        "conduct" => conduct,
        "blocking_rules" => blocking_rules,
        "coverage" => coverage,
        "core_spine" => core_spine,
        "shell_contract" => shell_contract.join("\n"),
        "task_contract_schema" => Master::Fix::TaskContract.agent_schema,
        "capabilities" => Operator::CapabilityManifest.new(root: REPO_ROOT).call,
      }
      payload["claim_check_map"] = claim_check_map if checks
      payload["tree"] = render_tree(root: tree_root, max_depth: tree_depth, max_entries: tree_max_entries) if tree
      payload
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if (options = Operator::AgentContext.fix_context_args(ARGV))
    target, full = options
    puts Operator::AgentContext.fix_context(target:, full:)
  elsif ARGV.include?("--json")
    require "json"
    tree = ARGV.include?("--tree")
    checks = ARGV.include?("--checks")
    root, depth, max_entries = tree ? Operator::AgentContext.tree_args(ARGV) : nil
    puts JSON.generate(Operator::AgentContext.session_json(
                         tree:,
                         tree_root: root,
                         tree_depth: depth,
                         tree_max_entries: max_entries,
                         checks:,
                       ))
  elsif (options = Operator::AgentContext.tree_args(ARGV))
    root, depth, max_entries = options
    puts Operator::AgentContext.render_tree(root:, max_depth: depth, max_entries:)
  else
    puts Operator::AgentContext.render(ARGV.first)
  end
end
