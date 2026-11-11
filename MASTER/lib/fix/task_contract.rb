# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Master
  module Fix
    # Validated task intent and preservation boundaries. This is procedure,
    # not a second source of Law.
    module TaskContract
      class Invalid < StandardError; end

      PATH = File.expand_path("../../data/task_contract.yml", __dir__).freeze
      REQUIRED = %w[intent scope preserve proof].freeze
      EVIDENCE_KEY = :master_fix_task_contract_preservation_evidence
      EVIDENCE_OVERFLOW_KEY = :master_fix_task_contract_preservation_evidence_overflow
      PLAN_KEY = :master_fix_task_contract_plan_digest
      MAX_PRESERVATION_ROWS = 256
      PRESERVATION_VERIFIERS = %w[artifact_preservation visual_custody].freeze
      PRESERVATION_DIMENSIONS_BY_CHECK = {
        "html_markup" => %w[structure],
        "inline_style_script_svg" => %w[visual_identity behavior assets],
        "html_visual_contract" => %w[visual_identity assets],
        "html_behavior_contract" => %w[behavior],
        "stylesheet_bytes" => %w[visual_identity],
        "protected_asset" => %w[assets],
        "protected_assets" => %w[assets],
        "rendered_visual_custody" => %w[visual_identity layout],
        "unchanged_bytes" => %w[visual_identity layout structure assets behavior accessibility public_contracts operator_owned_values product_identity content_semantics data_semantics],
      }.transform_values(&:freeze).freeze

      Contract = Data.define(:schema, :intent, :scope, :preserve, :proof, :new_paths) do
        def to_h
          value = {
            "schema" => schema,
            "intent" => intent,
            "scope" => scope,
            "preserve" => preserve,
            "proof" => proof,
          }
          value["new_paths"] = new_paths unless new_paths.empty?
          value
        end
      end

      module_function

      def template(path: PATH)
        schema = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        raise Invalid, "task contract schema must be version 1" unless schema.is_a?(Hash) && schema["schema"] == 1
        schema
      rescue Psych::Exception => error
        raise Invalid, "task contract schema is unreadable: #{error.message}"
      end

      def build(attributes = nil, path: PATH, **keyword_attributes)
        if attributes.nil?
          attributes = keyword_attributes
        elsif keyword_attributes.any?
          raise Invalid, "task contract attributes must be passed as one mapping"
        end
        raise Invalid, "task contract must be a mapping" unless attributes.is_a?(Hash)
        input = attributes.to_h { |key, value| [key.to_s, value] }
        schema = template(path:)
        optional = Array(schema.fetch("optional_fields", [])).map(&:to_s)
        missing = REQUIRED - input.keys
        raise Invalid, "task contract is missing: #{missing.join(', ')}" unless missing.empty?
        unknown = input.keys - REQUIRED - optional
        raise Invalid, "task contract has unknown fields: #{unknown.join(', ')}" unless unknown.empty?

        intent = input.fetch("intent").to_s
        policy = schema.fetch("intents")[intent]
        raise Invalid, "unknown task intent: #{intent.inspect}" unless policy.is_a?(Hash)

        scope = Array(input.fetch("scope")).map { |item| safe_path(item) }.uniq.sort
        raise Invalid, "task scope must name at least one repository-relative path" if scope.empty?
        allowed_preservation = Array(schema.fetch("preservation_dimensions")).map(&:to_s)
        preservation = Array(input.fetch("preserve")).map(&:to_s)
        unknown_preservation = preservation - allowed_preservation
        unless unknown_preservation.empty?
          raise Invalid, "unknown preservation dimension(s): #{unknown_preservation.join(', ')}"
        end
        required_preservation = Array(policy.fetch("must_preserve")).map(&:to_s)
        proof = Array(input.fetch("proof")).map(&:to_s)
        allowed_proof = Array(schema.fetch("proof_types")).map(&:to_s)
        unknown_proof = proof - allowed_proof
        raise Invalid, "unknown proof type(s): #{unknown_proof.join(', ')}" unless unknown_proof.empty?
        new_paths = normalize_new_paths(input.fetch("new_paths", []), scope:, schema:)

        Contract.new(
          schema.fetch("schema"),
          intent.freeze,
          scope.freeze,
          (preservation + required_preservation).uniq.sort.freeze,
          (proof + Array(schema.fetch("common_proof")).map(&:to_s)).uniq.sort.freeze,
          new_paths.freeze,
        ).freeze
      end

      # New paths are exact, task-scoped and justified. Globs can cover edits
      # to existing files; they are too broad to authorise new structure.
      def normalize_new_paths(value, scope:, schema:)
        raise Invalid, "task contract new_paths must be an array" unless value.is_a?(Array)

        fields = Array(schema.fetch("new_path_fields", %w[path reason])).map(&:to_s)
        rows = value.map do |row|
          raise Invalid, "each new_paths entry must be a mapping" unless row.is_a?(Hash)

          attributes = row.to_h { |key, item| [key.to_s, item] }
          missing = fields - attributes.keys
          unknown = attributes.keys - fields
          raise Invalid, "new_paths entry is missing: #{missing.join(', ')}" unless missing.empty?
          raise Invalid, "new_paths entry has unknown fields: #{unknown.join(', ')}" unless unknown.empty?

          path = safe_path(attributes.fetch("path"))
          raise Invalid, "new_paths requires an exact file path: #{path.inspect}" if path.match?(/[*?\[\]{}]/)
          raise Invalid, "new path is outside task-contract scope: #{path}" unless covers?(path, scope:)
          reason = attributes.fetch("reason").to_s.strip
          raise Invalid, "new_paths reason must be non-empty: #{path}" if reason.empty?

          { "path" => path.freeze, "reason" => reason.freeze }.freeze
        end
        duplicates = rows.map { |row| row.fetch("path") }.tally.select { |_path, count| count > 1 }.keys
        raise Invalid, "duplicate new_paths declaration(s): #{duplicates.join(', ')}" unless duplicates.empty?

        rows.freeze
      end

      def coerce(value, path: PATH)
        raise Invalid, "task contract must be a mapping or TaskContract::Contract" unless value.respond_to?(:to_h)

        attributes = value.to_h.transform_keys(&:to_s)
        version = attributes.delete("schema")
        raise Invalid, "unsupported task contract version: #{version.inspect}" if version && version != 1
        build(attributes, path:)
      end

      # The active contract is scoped to the synchronous Fix call. Nested calls
      # restore their caller's contract, and exceptions never leak it to later work.
      def current
        Thread.current[:master_fix_task_contract]
      end

      # Refuse unplanned file creation inside the repository, including legacy
      # callers that have no active task contract. Existing files remain editable;
      # a missing contract is an empty declaration, never an implicit allowance.
      # `declared` lets a caller whose own reviewed plan names the exact paths (a
      # restructure plan) stand as the declaration instead of a task contract.
      def new_path_refusal(path, contract: current, repo_root: nil, declared: [])

        root = File.expand_path(
          repo_root || (defined?(Master::REPO_ROOT) ? Master::REPO_ROOT : File.expand_path("../../..", __dir__))
        )
        absolute = File.expand_path(path.to_s, root)
        return unless absolute.start_with?(root + File::SEPARATOR)
        return if File.exist?(absolute) || File.symlink?(absolute)

        relative = absolute.delete_prefix(root + File::SEPARATOR)
        return if declared_paths(contract, declared).include?(relative)

        "new tracked path #{relative} is undeclared; extend an existing owner or declare the exact path and reason in task_contract.new_paths"
      end

      def declared_paths(contract, extra)
        from_contract = contract ? contract.new_paths.map { |entry| entry.fetch("path") } : []
        from_contract + Array(extra).map(&:to_s)
      end

      def with_current(value)
        previous = current
        previous_evidence = Thread.current[EVIDENCE_KEY]
        previous_overflow = Thread.current[EVIDENCE_OVERFLOW_KEY]
        previous_plan = Thread.current[PLAN_KEY]
        contract = value.nil? ? nil : coerce(value)
        Thread.current[:master_fix_task_contract] = contract
        unless contract && previous == contract
          Thread.current[EVIDENCE_KEY] = []
          Thread.current[EVIDENCE_OVERFLOW_KEY] = 0
          Thread.current[PLAN_KEY] = nil
        end
        yield
      ensure
        Thread.current[:master_fix_task_contract] = previous
        Thread.current[EVIDENCE_KEY] = previous_evidence
        Thread.current[EVIDENCE_OVERFLOW_KEY] = previous_overflow
        Thread.current[PLAN_KEY] = previous_plan
      end

      # Bind runtime preservation receipts to the immutable FixPlan.
      def attach_plan!(digest)
        return unless current

        Thread.current[PLAN_KEY] = digest.to_s
      end

      def record_preservation!(path:, format:, before:, after:, result:, verifier: "artifact_preservation")
        contract = current
        return unless contract

        repository = File.realpath(
          defined?(Master::REPO_ROOT) ? Master::REPO_ROOT : File.expand_path("../../..", __dir__)
        )
        absolute = File.expand_path(path.to_s)
        unless absolute.start_with?(repository + File::SEPARATOR)
          raise Invalid, "preservation path is outside the repository"
        end

        relative = absolute.delete_prefix(repository + File::SEPARATOR)
        raise Invalid, "preservation path is outside task-contract scope: #{relative}" unless
          covers?(relative, scope: contract.scope)

        cursor = repository
        relative.split(File::SEPARATOR).each do |segment|
          cursor = File.join(cursor, segment)
          next unless File.exist?(cursor) || File.symlink?(cursor)

          stat = File.lstat(cursor)
          raise Invalid, "preservation path contains a symlink: #{relative}" if stat.symlink?
          if cursor == absolute && stat.file? && stat.nlink != 1
            raise Invalid, "preservation path is hard-linked: #{relative}"
          end
        end
        verifier = verifier.to_s
        unless PRESERVATION_VERIFIERS.include?(verifier)
          raise Invalid, "unregistered preservation verifier: #{verifier}"
        end

        value = result.to_h
        status = (value[:status] || value["status"]).to_s
        raise Invalid, "unknown preservation result status: #{status}" unless %w[PASS FAIL INCONCLUSIVE].include?(status)

        checks = Array(value[:checks] || value["checks"]).map(&:to_s).uniq
        if verifier == "visual_custody" && !checks.include?("rendered_visual_custody")
          raise Invalid, "visual custody receipt must name rendered_visual_custody"
        end
        dimensions = checks.flat_map { |check| PRESERVATION_DIMENSIONS_BY_CHECK.fetch(check, []) }.uniq
        contract_digest = Digest::SHA256.hexdigest(JSON.generate(contract.to_h))
        row = {
          "path" => relative,
          "format" => format.to_s.downcase.delete_prefix("."),
          "intent" => contract.intent,
          "verifier" => verifier,
          "evidence_level" => verifier == "artifact_preservation" ? "source_level" : "runtime_or_external",
          "status" => status,
          "checks" => checks,
          "dimensions" => dimensions,
          "reason" => (value[:reason] || value["reason"])&.to_s&.slice(0, 300),
          "before_sha256" => Digest::SHA256.hexdigest(before.to_s.b),
          "after_sha256" => Digest::SHA256.hexdigest(after.to_s.b),
          "contract_digest" => contract_digest,
          "plan_digest" => Thread.current[PLAN_KEY],
        }.compact
        rows = Thread.current[EVIDENCE_KEY] ||= []
        if rows.size >= MAX_PRESERVATION_ROWS
          # Keep the original receipt set intact. Silently dropping its oldest
          # rows would let a truncated population look like complete evidence.
          Thread.current[EVIDENCE_OVERFLOW_KEY] = Thread.current[EVIDENCE_OVERFLOW_KEY].to_i + 1
          return row.freeze
        end
        rows << row.freeze
        row
      end

      # Source-level checks are never promoted into full rendered/runtime/
      # accessibility preservation proof.
      def preservation_evidence
        contract = current
        rows = Array(Thread.current[EVIDENCE_KEY])
        return { "status" => "not_measured", "results" => [] } unless contract

        statuses = rows.map { |row| row["status"] }
        required = contract.preserve
        covered = rows.flat_map { |row| Array(row["dimensions"]) }.uniq
        missing = required - covered
        source_only = rows.any? { |row| row["evidence_level"] == "source_level" }
        missing_plan = Thread.current[PLAN_KEY].to_s.empty?
        overflow_count = Thread.current[EVIDENCE_OVERFLOW_KEY].to_i
        status = if statuses.include?("FAIL")
                   "FAIL"
                 elsif rows.empty?
                   "not_measured"
                 elsif statuses.any? { |value| value != "PASS" } || source_only || missing.any? || missing_plan || overflow_count.positive?
                   "INCONCLUSIVE"
                 else
                   "PASS"
                 end
        reasons = []
        reasons << "source-level checks do not prove rendered, runtime or accessibility preservation" if source_only
        reasons << "required preservation dimensions unmeasured: #{missing.join(', ')}" if missing.any?
        reasons << "preservation receipts are not bound to a FixPlan" if missing_plan
        reasons << "#{overflow_count} additional preservation receipt(s) exceeded the #{MAX_PRESERVATION_ROWS}-row evidence limit" if overflow_count.positive?
        {
          "status" => status,
          "contract_digest" => Digest::SHA256.hexdigest(JSON.generate(contract.to_h)),
          "plan_digest" => Thread.current[PLAN_KEY],
          "required_dimensions" => required,
          "covered_dimensions" => covered.sort,
          "missing_dimensions" => missing.sort,
          "result_count" => rows.size,
          "overflow_count" => overflow_count,
          "results" => rows.dup,
          "reason" => reasons.empty? ? nil : reasons.join("; "),
        }.compact
      end

      def covers?(path, scope:)
        candidate = path.to_s
        Array(scope).any? do |entry|
          pattern = entry.to_s
          if pattern.end_with?("/**")
            prefix = pattern.delete_suffix("/**").delete_suffix("/")
            next true if candidate == prefix || candidate.start_with?("#{prefix}/")
          end
          prefix = pattern.delete_suffix("/")
          next true if candidate == prefix
          next true if !pattern.match?(/[*?\[\]{}]/) && candidate.start_with?("#{prefix}/")

          File.fnmatch?(pattern, candidate, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end

      def agent_schema(path: PATH)
        schema = template(path:)
        {
          "schema" => schema.fetch("schema"),
          "required_fields" => schema.fetch("required_fields"),
          "optional_fields" => schema.fetch("optional_fields", []),
          "new_path_fields" => schema.fetch("new_path_fields", %w[path reason]),
          "common_proof" => schema.fetch("common_proof"),
          "intents" => schema.fetch("intents").transform_values { |value| value.slice("description", "must_preserve") },
        }
      end

      def prompt(path: PATH)
        schema = template(path:)
        rows = schema.fetch("intents").map do |name, policy|
          "  #{name}: #{policy.fetch("description")} Must preserve: #{Array(policy.fetch("must_preserve")).join(", ")}"
        end
        [
          "Use a task contract before planning edits. Required fields: #{REQUIRED.join(", ")}.",
          "Intent is explicit; choose the narrowest mode supported by the request. Do not silently promote a content edit into a redesign.",
          *rows,
          "Scope paths are repository-relative. Preserve all mandatory dimensions for the selected intent.",
          "Existing paths are the default: extend the nearest owner and its existing tests before adding a tracked file.",
          "A missing task contract is an empty new_paths declaration: automated writes may edit existing repository paths but must refuse every new tracked path unless its exact path and reason are declared in an active contract.",
          "A new tracked file needs an exact path and non-empty reason in optional new_paths, inside the task scope. A new directory needs a genuine ownership boundary; never create helpers, tests, docs, config or utility folders merely for convenience.",
          "Proof always includes baseline hashes, a path-scoped diff and a Law assessment. Add relevant tests, rendered/runtime evidence, accessibility review, citations or human review.",
          "If a required measurement is absent or a format has no verifier, report INCONCLUSIVE or NOT_RUN; do not infer PASS.",
          "Schema: MASTER/data/task_contract.yml.",
        ].join("\n")
      end

      def safe_path(value)
        path = value.to_s.strip.delete_suffix("/")
        segments = path.split("/")
        if path.empty? || path.start_with?("/", "~") || path.include?("\\") || path.include?("\0") ||
           segments.any? { |segment| segment.empty? || segment == "." || segment == ".." } ||
           path.match?(/\A[A-Za-z]:/)
          raise Invalid, "task scope path must be repository-relative: #{path.inspect}"
        end
        path
      end
    end
  end
end
