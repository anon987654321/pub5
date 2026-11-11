# frozen_string_literal: true

require "securerandom"
require_relative "../execution/contract"

module Master
  module Trace
    # Bridges the Fold's effect lifecycle to the event bus's strict persistence
    # API. The Fold does not depend on Trace; hosts inject this callable adapter.
    class EffectObserver
      BEFORE_EVENT = "core:effect:before"
      AFTER_EVENT = "core:effect:after"

      def initialize(bus:, run_id: SecureRandom.uuid, attempt_id: nil, mission_id: nil)
        raise ArgumentError, "effect audit requires publish_required" unless bus.respond_to?(:publish_required)

        @bus = bus
        @run_id = Master::Execution::Contract.token!(run_id, "run id")
        @attempt_id = Master::Execution::Contract.token!(attempt_id, "attempt id") if attempt_id
        @mission_id = Master::Execution::Contract.token!(mission_id, "mission id") if mission_id
        @lifecycle_mutex = Mutex.new
        @pending_effects = {}
        @completed_effects = {}
        restore_lifecycle_history!
      end

      def call(stage:, turn:, effect:, effect_id:, operation: :perform, parent_effect_id: nil,
               checkpoint_id: nil, run_id: nil, attempt_id: nil, mission_id: nil, scope: nil,
               idempotency_key: nil, deadline_at: nil, reversibility: :unknown, evidence_refs: [],
               observation: nil, elapsed_ms: nil)
        payload = Master::Execution::Contract::EffectEnvelope.build(
          effect:, turn:, effect_id:, operation:, parent_effect_id:, checkpoint_id:,
          run_id: run_id || @run_id, attempt_id: attempt_id || @attempt_id,
          mission_id: mission_id || @mission_id, scope:,
          idempotency_key:, deadline_at:, reversibility:
        ).to_h
        identity = payload.dup.freeze
        references = safe_evidence_refs(evidence_refs)
        payload[:evidence_refs] = references unless references.empty?

        case stage.to_sym
        when :before
          publish_before(identity, payload)
        when :after
          publish_after(identity, payload, observation, elapsed_ms)
        else
          raise ArgumentError, "unknown effect lifecycle stage: #{stage}"
        end
      end

      private

      def safe_evidence_refs(references)
        Array(references).map do |reference|
          unless reference.is_a?(Master::Execution::Contract::EvidenceReference)
            raise ArgumentError, "evidence refs must use the typed EvidenceReference contract"
          end

          reference.to_h
        end
      end

      # Persisted before/after events are a protocol, not unrelated log lines.
      # Startup replays the bounded durable history to restore duplicate-ID
      # protection; this in-process guard then catches duplicate IDs and
      # mismatched after-events. It is not a cross-process exactly-once ledger:
      # callers still reconcile uncertain external effects before retrying.
      def publish_before(identity, payload)
        with_durable_lifecycle_lock do
          refresh_lifecycle_history! if @bus.respond_to?(:effect_history)
          key = effect_key(identity)
          @lifecycle_mutex.synchronize do
            if @pending_effects.key?(key) || @completed_effects.key?(key)
              raise ArgumentError, "duplicate before-event for effect identity"
            end

            @bus.publish_required(BEFORE_EVENT, payload.merge(pid: Process.pid))
            @pending_effects[key] = identity
          end
        end
      end

      def publish_after(identity, payload, observation, elapsed_ms)
        raise ArgumentError, "after-event requires an observation" unless observation

        elapsed_ms = checked_elapsed_ms(elapsed_ms)
        with_durable_lifecycle_lock do
          refresh_lifecycle_history! if @bus.respond_to?(:effect_history)
          key = effect_key(identity)
          @lifecycle_mutex.synchronize do
            expected = @pending_effects[key]
            raise ArgumentError, "after-event requires a matching before-event" unless expected
            raise ArgumentError, "after-event identity differs from its before-event" unless expected == identity

            @bus.publish_required(
              AFTER_EVENT,
              payload.merge(status: observation.ok? ? "ok" : "error", elapsed_ms:),
            )
            @pending_effects.delete(key)
            @completed_effects[key] = true
          end
        end
      end

      # Rebuild duplicate-ID protection from the operational receipt stream.
      # A before-event without an after-event remains pending; it is never
      # guessed to have succeeded or failed after a process restart.
      def restore_lifecycle_history!
        pending = {}
        completed = {}
        lifecycle_history.each do |record|
          raise IOError, "effect history contains a non-mapping record" unless record.is_a?(Hash)

          event = record["event"].to_s
          next unless [BEFORE_EVENT, AFTER_EVENT].include?(event)

          payload = record["payload"]
          raise IOError, "effect history contains a malformed lifecycle payload" unless payload.is_a?(Hash)

          identity = identity_from_history(payload)
          raise IOError, "effect history contains an invalid lifecycle identity" unless identity

          key = effect_key(identity)
          if event == BEFORE_EVENT
            pending[key] = identity
            completed.delete(key)
          else
            pending.delete(key)
            completed[key] = true
          end
        end
        @lifecycle_mutex.synchronize do
          @pending_effects.replace(pending)
          @completed_effects.replace(completed)
        end
      end

      def lifecycle_history
        @bus.respond_to?(:effect_history) ? @bus.effect_history : []
      end

      def identity_from_history(payload)
        fields = %i[
          effect_id turn verb capability operation parent_effect_id checkpoint_id
          run_id attempt_id mission_id scope_digest idempotency_key deadline_at reversibility
        ]
        attributes = fields.each_with_object({}) do |field, result|
          key = field.to_s
          result[field] = payload[key] if payload.key?(key)
        end
        Master::Execution::Contract::EffectEnvelope.new(**attributes).to_h.freeze
      rescue ArgumentError, TypeError
        nil
      end

      def effect_key(payload)
        payload[:effect_id].to_s.freeze
      end

      def with_durable_lifecycle_lock
        if @bus.respond_to?(:synchronize_effect_lifecycle)
          @bus.synchronize_effect_lifecycle { yield }
        else
          yield
        end
      end

      def checked_elapsed_ms(value)
        return if value.nil?

        elapsed = Integer(value)
        raise ArgumentError, "elapsed_ms must be non-negative" if elapsed.negative?

        elapsed
      rescue TypeError, ArgumentError => e
        raise e if e.message == "elapsed_ms must be non-negative"

        raise ArgumentError, "elapsed_ms must be a non-negative integer"
      end
    end
  end
end
