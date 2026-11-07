# frozen_string_literal: true

module Shared
  # First-party last-click attribution. Only authenticated, non-guest accounts
  # are persisted; raw session identifiers and IP addresses are never stored.
  class S2sAttribution < ApplicationRecord
    self.table_name = "s2s_attributions"
    belongs_to :user, class_name: "::User"

    class << self
      def capture!(user:, params:)
        return if user.blank? || user.guest? || user.deleted_at.present?
        mediago = safe_click_id(params["tracking_id"].presence || params["trackingid"].presence || params["mediago_trackingid"])
        revcontent = safe_click_id(params["rc_uuid"])
        return if mediago.blank? && revcontent.blank?

        row = find_or_initialize_by(user:)
        row.assign_attributes(mediago_tracking_id: mediago.presence || row.mediago_tracking_id,
                              revcontent_rc_uuid: revcontent.presence || row.revcontent_rc_uuid,
                              captured_at: Time.current)
        row.save!
      end

      def enqueue_conversion(user_id:, reference:, amount_cents:, currency: "NOK")
        return if user_id.blank? || reference.blank? || amount_cents.to_i.negative?
        return unless exists?(user_id:)

        conversion = S2sConversion.create_or_find_by!(user_id:, reference: reference.to_s.first(200)) do |row|
          row.amount_cents = amount_cents.to_i
          row.currency = currency.to_s.upcase.first(8).presence || "NOK"
          row.converted_at = Time.current
        end
        S2sPostbackJob.perform_later(conversion.id) if conversion.previously_new_record?
        conversion
      end

      private

      def safe_click_id(value)
        value = value.to_s
        return if value.blank? || value.bytesize > 500 || value.match?(/[[:cntrl:]]/)
        value
      end
    end
  end
end
