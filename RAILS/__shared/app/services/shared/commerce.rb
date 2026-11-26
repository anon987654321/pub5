# frozen_string_literal: true

require "uri"

module Shared
  module Commerce
    PROTOCOL = "pub4-commerce-v1".freeze
    SOURCES = %w[brgen amber].freeze

    Reference = Data.define(:id, :source, :type, :url)
    Candidate = Data.define(
      :id, :title, :description, :merchant, :category, :price_cents, :currency,
      :condition, :availability, :delivery, :trust, :url, :image_url, :reasons, :metadata
    )

    EVENT_NAMES = %w[
      product_viewed
      product_clicked
      cart_added
      offer_sent
      purchase_completed
      order_shipped
      order_delivered
      return_started
      return_completed
    ].freeze

    module_function

    def canonical_id(source:, type:, city_id: nil, record_id:)
      parts = [ PROTOCOL, source.to_s, type.to_s, (city_id if city_id.present?), record_id ].compact
      parts.join(":")
    end

    def normalize_query(value)
      value.to_s.downcase.scan(/[[:alnum:]]+/).uniq.first(8)
    end

    def score(value)
      value.to_f.clamp(0.0, 1.0).round(4)
    end

    def reason(code:, text:)
      { code: code.to_s, text: text.to_s }
    end

    def valid_event?(name)
      EVENT_NAMES.include?(name.to_s)
    end

    def amber_handoff_url(base:, title:, category:, source_url:, commerce_key:)
      query = URI.encode_www_form(
        {
          title: title.to_s,
          category: category.to_s.presence,
          source_url: source_url.to_s,
          commerce_key: commerce_key.to_s,
        }.compact
      )
      "#{base.to_s.sub(%r{/$}, "")}/items/new?#{query}"
    rescue StandardError
      nil
    end
    # The first durable journal slice records credits and entitlements only.
    # Payment providers and checkout remain on their existing paths until their
    # contracts can be unified without changing live money movement.
    module Ledger
      IDEMPOTENCY_KEY = /\A[a-z0-9][a-z0-9:._-]{2,159}\z/
      METADATA_KEYS = %w[vertical].freeze
      COMPARISON_FIELDS = %i[
        entry_type user_id actor_id source_type source_id entitlement
        expires_at amount_minor currency metadata
      ].freeze

      class IdempotencyConflict < StandardError; end

      module_function

      def record_credit!(credit)
        raise ArgumentError, "credit must be persisted" unless credit.respond_to?(:persisted?) && credit.persisted?

        actor_id = Shared::ReferralSplinter.where(id: credit.referral_splinter_id).pick(:redeemed_by_id)
        raise ArgumentError, "referral credit has no redeemer" unless actor_id

        record!(
          idempotency_key: "referral-credit:#{credit.id}",
          entry_type: "credit_granted",
          user_id: credit.user_id,
          actor_id:,
          source: credit,
          entitlement: credit.entitlement,
          expires_at: credit.expires_at,
          metadata: { vertical: credit.vertical }
        )
      end

      # An idempotency key names one immutable fact. Replays return the original
      # row; reusing a key for different facts is a conflict, never an update.
      def record!(idempotency_key:, entry_type:, user_id:, actor_id: nil, source: nil,
                  entitlement:, expires_at: nil, amount_minor: nil, currency: nil, metadata: {})
        key = idempotency_key.to_s
        raise ArgumentError, "invalid ledger idempotency key" unless key.match?(IDEMPOTENCY_KEY)

        type = entry_type.to_s
        raise ArgumentError, "unknown ledger entry type" unless Shared::CommerceLedgerEntry::ENTRY_TYPES.include?(type)

        source_type, source_id = source_identity(source)
        amount = amount_minor.nil? ? nil : Integer(amount_minor)
        raise ArgumentError, "ledger amount cannot be negative" if amount&.negative?

        currency_code = currency.to_s.strip.upcase.presence
        if amount.nil? != currency_code.nil?
          raise ArgumentError, "ledger amount and currency must be supplied together"
        end
        raise ArgumentError, "invalid ledger currency" if currency_code && !currency_code.match?(/\A[A-Z]{3}\z/)

        attributes = {
          entry_type: type,
          user_id: Integer(user_id),
          actor_id: actor_id.nil? ? nil : Integer(actor_id),
          source_type:,
          source_id:,
          entitlement: entitlement.to_s,
          expires_at:,
          amount_minor: amount,
          currency: currency_code,
          metadata: normalize_metadata(metadata),
        }

        raise ArgumentError, "ledger entitlement is required" if attributes[:entitlement].blank?
        raise ArgumentError, "credit grant needs an expiry" if type == "credit_granted" && expires_at.blank?

        entry = Shared::CommerceLedgerEntry.create_or_find_by!(idempotency_key: key) do |row|
          row.assign_attributes(attributes)
        end
        assert_same_event!(entry, attributes)
        entry
      end

      def source_identity(source)
        return [ nil, nil ] if source.nil?
        raise ArgumentError, "ledger source must be persisted" unless source.respond_to?(:persisted?) && source.persisted?

        [ source.class.base_class.name, Integer(source.id) ]
      end
      private_class_method :source_identity

      def normalize_metadata(metadata)
        raise ArgumentError, "ledger metadata must be a Hash" unless metadata.is_a?(Hash)

        normalized = metadata.transform_keys(&:to_s)
        unknown = normalized.keys - METADATA_KEYS
        raise ArgumentError, "unsupported ledger metadata: #{unknown.join(', ')}" if unknown.any?

        vertical = normalized["vertical"]
        if vertical
          value = vertical.to_s
          raise ArgumentError, "invalid ledger vertical" unless value.match?(/\A[a-z][a-z0-9_]{1,31}\z/)
          { "vertical" => value }
        else
          {}
        end
      end
      private_class_method :normalize_metadata

      def assert_same_event!(entry, attributes)
        conflicts = COMPARISON_FIELDS.select do |field|
          entry.public_send(field) != attributes.fetch(field)
        end
        return entry if conflicts.empty?

        raise IdempotencyConflict, "ledger key already records different facts: #{conflicts.join(', ')}"
      end
      private_class_method :assert_same_event!
    end
  end
end
