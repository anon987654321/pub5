# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "restructure"
require_relative "transformation_plan"
require_relative "commit_message"
require_relative "rails_app"

module Master
  module Fix
    # Named, reviewed inputs to the existing multi-file Restructure pipeline.
    # Recipes contain complete file targets and a single constitutional
    # transformation; they do not contain shell commands or a second executor.
    class StructuralRecipes
      PATH = File.expand_path("../../data/structural_recipes.yml", __dir__)
      TREES = %w[MASTER RAILS OPENBSD STUDIO BIZ].freeze
      RECIPE_KEYS = %w[description operation plan proofs summary tree].freeze
      PROOF_KEYS = %w[app kind path].freeze
      APPROVAL = /\AAPPROVE:\s+\S.{19,}\z/.freeze
      TEST_SUMMARY = /\A\s*(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors(?:, \d+ skips)?\s*\z/.freeze

      Recipe = Data.define(:name, :description, :tree, :operation, :summary, :plan, :proofs)

      class Invalid < StandardError; end

      def initialize(repo_root: Master::REPO_ROOT, catalogue_path: PATH)
        @root = File.expand_path(repo_root)
        @catalogue_path = File.expand_path(catalogue_path)
        @recipes = nil
      end

      def list
        recipes.values.sort_by(&:name).map { |recipe| [recipe.name, recipe.description] }
      end

      def fetch(name)
        recipes.fetch(name.to_s) { raise Invalid, "unknown structural recipe #{name.inspect}" }
      end

      # Dry-run shares the exact Restructure plan validation and path gates used
      # by apply. The returned diff is generated from current bytes, not a
      # predicted command list.
      def preview(name)
        recipe = fetch(name)
        result = restructure(recipe).preview(recipe.plan, allowed_operations: [recipe.operation])
        return result unless result.ok?

        Master::Result.ok(result.value!.merge(name: recipe.name, description: recipe.description))
      rescue Invalid => error
        Master::Result.err(error.message, category: :validation)
      rescue StandardError => error
        Master::Result.err("structural recipe preview: #{error.class}: #{error.message}", category: :infrastructure)
      end

      # Apply only after the caller explicitly selected --apply. A recipe that
      # already matches disk runs its proofs and returns a no-op; drift uses the
      # existing Restructure snapshots, hostile review, Rails proof and delivery.
      def apply(name, agent:)
        recipe = fetch(name)
        preview_result = preview(name)
        return preview_result unless preview_result.ok?

        preview = preview_result.value!
        if preview.fetch(:already_applied)
          failure = run_declared_proofs(recipe) || existing_tree_proof_failure(recipe)
          return Master::Result.err("recipe proof failed: #{failure}", category: :validation) if failure

          return Master::Result.ok(
            state: :already_applied,
            name: recipe.name,
            paths: recipe.plan.paths,
            message: "already applied; declared Rails test and RAILS restructure proof passed",
          )
        end

        unless agent&.respond_to?(:ask)
          return Master::Result.err("apply requires a configured review agent; no files changed", category: :policy)
        end

        review = lambda do |diff|
          answer = agent.ask(review_prompt(recipe, diff), operation: :restructure).to_s.strip
          next "hostile review rejected recipe: #{answer.lines.first.to_s.strip[0, 220]}" unless answer.match?(APPROVAL)

          run_declared_proofs(recipe)
        rescue StandardError => error
          "recipe review unavailable: #{error.class}: #{error.message}"
        end

        result = restructure(recipe).call(
          recipe.plan,
          message: commit_message(recipe),
          review:,
          allowed_operations: [recipe.operation],
        )
        return result unless result.ok?

        value = result.value!
        Master::Result.ok(value.merge(name: recipe.name, state: :delivered))
      rescue Invalid => error
        Master::Result.err(error.message, category: :validation)
      rescue StandardError => error
        Master::Result.err("structural recipe apply: #{error.class}: #{error.message}", category: :infrastructure)
      end

      private

      def recipes
        return @recipes if @recipes

        document = YAML.safe_load_file(@catalogue_path, aliases: false)
        raise Invalid, "recipe catalogue must contain schema and recipes" unless
          document.is_a?(Hash) && document.keys.sort == %w[recipes schema]
        raise Invalid, "unsupported structural recipe schema" unless document.fetch("schema") == 1

        rows = document.fetch("recipes")
        raise Invalid, "structural recipe catalogue is empty" unless rows.is_a?(Hash) && !rows.empty?

        @recipes = rows.to_h do |name, row|
          [name.to_s, build_recipe(name.to_s, row)]
        end.freeze
      rescue Psych::Exception => error
        raise Invalid, "structural recipe YAML is invalid: #{error.message}"
      end

      def build_recipe(name, row)
        raise Invalid, "invalid recipe name #{name.inspect}" unless name.match?(/\A[a-z][a-z0-9_]*\z/)
        raise Invalid, "#{name}: recipe must be a mapping" unless row.is_a?(Hash)
        raise Invalid, "#{name}: recipe fields differ from the schema" unless row.keys.sort == RECIPE_KEYS

        description = required_text(row, "description", name)
        tree = required_text(row, "tree", name)
        operation = required_text(row, "operation", name)
        summary = required_text(row, "summary", name)
        raise Invalid, "#{name}: unknown tree #{tree}" unless TREES.include?(tree)

        plan_text = required_text(row, "plan", name)
        plan = Restructure::Plan.parse(plan_text)
        raise Invalid, "#{name}: plan summary does not match recipe summary" unless plan.summary == summary
        raise Invalid, "#{name}: plan must contain exactly its declared operation" unless plan.operations == [operation]
        raise Invalid, "#{name}: plan contains no file changes" if plan.empty?
        raise Invalid, "#{name}: plan exceeds Restructure's file limits" if
          plan.paths.size > Restructure::MAX_FILES || plan.writes.size > Restructure::MAX_WRITES ||
          plan.deletes.size > Restructure::MAX_DELETES
        raise Invalid, "#{name}: only one explicitly named deletion is allowed" if plan.deletes.size > 1
        raise Invalid, "#{name}: duplicate paths in plan" unless plan.paths.uniq == plan.paths

        plan.paths.each { |path| validate_path!(name, tree, path) }
        proofs = validate_proofs!(name, row.fetch("proofs"))
        Recipe.new(name.freeze, description.freeze, tree.freeze, operation.freeze, summary.freeze, plan, proofs)
      end

      def required_text(row, key, name)
        value = row.fetch(key)
        raise Invalid, "#{name}: #{key} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?

        value
      end

      def validate_path!(name, tree, path)
        parts = path.to_s.split("/")
        unless path.start_with?("#{tree}/") && !Pathname.new(path).absolute? && !parts.include?("..") &&
            !parts.include?(".") && !path.match?(/[\x00-\x1f]/)
          raise Invalid, "#{name}: unsafe or out-of-tree path #{path.inspect}"
        end

        current = @root
        parts.each do |part|
          current = File.join(current, part)
          raise Invalid, "#{name}: symlinked path component refused: #{path}" if File.symlink?(current)
        end
        true
      end

      def validate_proofs!(name, proofs)
        raise Invalid, "#{name}: at least one declared proof is required" unless proofs.is_a?(Array) && !proofs.empty?

        proofs.map do |proof|
          raise Invalid, "#{name}: proof must be a mapping" unless proof.is_a?(Hash) && proof.keys.sort == PROOF_KEYS
          raise Invalid, "#{name}: only typed rails_test proofs are supported" unless proof["kind"] == "rails_test"

          app = proof["app"].to_s
          relative = proof["path"].to_s
          app_root = RailsApp.app_dir(app, repo_root: @root)
          raise Invalid, "#{name}: proof names an unregistered Rails app #{app.inspect}" unless app_root
          unless relative.start_with?("test/") && !relative.split("/").include?("..") &&
              File.file?(File.join(app_root, relative))
            raise Invalid, "#{name}: proof path is not a tracked app test: #{app}/#{relative}"
          end

          proof.transform_values { |value| value.to_s.freeze }.freeze
        end.freeze
      end

      def restructure(recipe)
        Restructure.new(
          repo_root: @root,
          tree: recipe.tree,
          transformation_plan: TransformationPlan.new(root: Master::ROOT),
        )
      end

      def run_declared_proofs(recipe)
        recipe.proofs.each do |proof|
          app_root = RailsApp.app_dir(proof.fetch("app"), repo_root: @root)
          output, status = RailsApp.capture(
            app_root, "bin/rails", "test", proof.fetch("path"),
            timeout: Restructure::Proof::TIMEOUT_S,
            env: { "RAILS_ENV" => "test" },
          )
          summary = output.lines.reverse.filter_map { |line| line.match(TEST_SUMMARY) }.first
          unless status.success? && summary && summary[1].to_i.positive? &&
              summary[2].to_i.zero? && summary[3].to_i.zero?
            detail = output.lines.last(8).join.strip
            return "#{proof.fetch("app")}/#{proof.fetch("path")} did not prove green (exit #{status.exitstatus}): #{detail[0, 500]}"
          end
        end
        nil
      rescue StandardError => error
        "#{error.class}: #{error.message}"
      end

      def existing_tree_proof_failure(recipe)
        proof = Restructure::Proof.for(recipe.tree, @root)
        before = proof.baseline(recipe.plan)
        proof.failure(recipe.plan, before)
      rescue StandardError => error
        "#{error.class}: #{error.message}"
      end

      def review_prompt(recipe, diff)
        <<~PROMPT
          You are the hostile reviewer for a named structural recipe.
          Recipe: #{recipe.name}
          Summary: #{recipe.summary}
          Transformation: #{recipe.operation}
          Scope: #{recipe.plan.paths.join(", ")}

          Verify the diff against the description and public Rails contracts.
          Reject speculative deletion, changed route/helper behavior, unrelated
          edits, loss of namespace compatibility, or a plan that does not earn
          its complexity. The recipe's declared Rails test runs before this
          review; the RAILS Restructure proof runs after it.

          Reply with exactly one line:
          APPROVE: <at least twenty characters explaining why the bounded change is safe>
          or
          REJECT: <reason>

          DIFF:
          #{diff}
        PROMPT
      end

      def commit_message(recipe)
        CommitMessage.compose(
          recipe.summary,
          what: "The named structural recipe updates #{recipe.plan.paths.size} scoped file(s)",
          why: "Its declared Rails test, hostile review and RAILS tree proof must all hold",
        )
      end
    end
  end
end
