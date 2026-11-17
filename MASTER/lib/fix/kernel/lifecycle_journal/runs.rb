# frozen_string_literal: true

module Master
  module Fix
    class Kernel
      # Plan binding and pass-lifecycle mutations on the durable run journal:
      # provenance invalidation, pass start/finish, convergence state, terminal
      # and crashed states.
      class LifecycleJournal
        # Every dimension a plan generation is bound by; a change in any of
        # them invalidates persisted convergence rather than resuming it.
        PLAN_PROVENANCE_DIMENSIONS = %w[
          scope_digest source_digest law_digest law_source_digest authority_digest
          toolchain_digest exclusion_digest adapter_digest identity_digest
        ].freeze

        # Bind immutable evidence provenance to the existing durable run. A
        # source, scope, Law, authority, toolchain or adapter change invalidates
        # persisted convergence rather than resuming an old clean streak.
        def bind_plan(run_id, plan)
          manifest = plan.respond_to?(:to_h) ? plan.to_h : plan
          raise ArgumentError, "fix plan manifest must be a hash" unless manifest.is_a?(Hash)

          receipt = nil
          update(run_id) do |run|
            previous = run["plan"]
            changed = bind_plan_changed_dimensions(run, previous, manifest)
            receipt = bind_plan_apply!(run, manifest, previous, changed)
          end
          emit(
            "fix:plan_bound",
            run_id:,
            plan_digest: manifest["digest"],
            source_digest: manifest["source_digest"],
            scope_digest: manifest["scope_digest"],
            generation: receipt && receipt[:generation],
            convergence_invalidated: receipt && receipt[:invalidated],
            changed_dimensions: receipt && receipt[:dimensions],
          )
          receipt
        end

        def pass_start(run_id, pass, transaction_id:)
          update(run_id) do |run|
            run["passes"] << {
              "pass" => pass.to_i,
              "state" => "active",
              "transaction_id" => transaction_id.to_s,
              "started_at" => Time.now.utc.iso8601,
            }
          end
        end

        def save_convergence_state(run_id, checkpoint, pass_state: nil)
          raise ArgumentError, "convergence checkpoint must be a hash" unless checkpoint.is_a?(Hash)
          raise ArgumentError, "pass state must be a hash" if !pass_state.nil? && !pass_state.is_a?(Hash)

          update(run_id) do |run|
            run["convergence_state"] = checkpoint
            run["pass_state"] = pass_state if pass_state
          end
        end

        def pass_finish(run_id, pass, status:, message: nil)
          update(run_id) do |run|
            entry = Array(run["passes"]).reverse.find { |row| row["pass"].to_i == pass.to_i }
            next unless entry

            entry["state"] = status.to_s
            entry["message"] = message.to_s[0, 400] unless message.nil?
            entry["finished_at"] = Time.now.utc.iso8601
          end
        end

        def terminal(run_id, state, message: nil, evidence: nil)
          terminal_state = OutcomePolicy.normalize_state(state)
          unless terminal_state
            raise ArgumentError, "unknown /fix terminal state: #{state.inspect}"
          end

          update(run_id) do |run|
            run["state"] = terminal_state.to_s
            run["message"] = message.to_s[0, 400] unless message.nil?
            run["evidence"] = evidence if evidence.is_a?(Hash)
            run["finished_at"] = Time.now.utc.iso8601
          end
        end

        def crash(run_id, error)
          update(run_id) do |run|
            run["state"] = "crashed"
            run["error"] = error.to_s[0, 800]
            run["finished_at"] = Time.now.utc.iso8601
          end
        end

        private

        def update(run_id)
          with_lock do
            data = load
            run = data["runs"].find { |row| row["id"] == run_id }
            return unless run

            yield run
            persist(data, run_id:)
          end
        end

        def bind_plan_changed_dimensions(run, previous, manifest)
          return PLAN_PROVENANCE_DIMENSIONS.select { |key| previous[key] != manifest[key] } if previous.is_a?(Hash)
          return ["missing_prior_plan"] if run.key?("convergence_state") || run.key?("pass_state")

          []
        end

        def bind_plan_invalidate!(run, previous, manifest, changed)
          run.delete("convergence_state")
          run.delete("pass_state")
          run["convergence_invalidated"] = {
            "at" => Time.now.utc.iso8601,
            "dimensions" => changed,
            "previous_source_digest" => previous["source_digest"],
            "current_source_digest" => manifest["source_digest"],
          }
        end

        def bind_plan_apply!(run, manifest, previous, changed)
          invalidated = changed.any?
          bind_plan_invalidate!(run, previous, manifest, changed) if invalidated

          plans = Array(run["plan_generations"])
          generation = if previous.nil? || invalidated
                         bind_plan_record_generation!(run, plans, manifest)
                       else
                         (plans.map { |row| row["generation"].to_i }.max || 0).to_i
                       end

          run["plan"] = manifest
          { invalidated:, dimensions: changed, generation:, plan: manifest }
        end

        def bind_plan_record_generation!(run, plans, manifest)
          generation = (plans.map { |row| row["generation"].to_i }.max || -1).to_i + 1
          plans << {
            "generation" => generation,
            "digest" => manifest["digest"],
            "scope_digest" => manifest["scope_digest"],
            "source_digest" => manifest["source_digest"],
            "law_digest" => manifest["law_digest"],
            "created_at" => manifest["created_at"],
          }
          run["plan_generations"] = plans.last(8)
          generation
        end
      end
    end
  end
end
