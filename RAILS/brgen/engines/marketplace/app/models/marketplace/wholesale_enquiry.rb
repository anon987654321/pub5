# frozen_string_literal: true

require "uri"

module Marketplace
  # A trade request is deliberately not an order. Unit prices, stock, minimum
  # order quantities and payment terms belong to the supplier's confirmed reply,
  # not to invented catalogue data or the consumer checkout.
  class WholesaleEnquiry < ApplicationRecord
    include Shared::Notifiable

    self.table_name = "marketplace_wholesale_enquiries"

    STATUSES = %w[submitted responded].freeze

    belongs_to :store, class_name: "Marketplace::Store"
    belongs_to :buyer, class_name: "User"

    validates :buyer_company_name, :contact_name, :contact_email,
              :requested_items, :delivery_location, presence: true
    validates :buyer_company_name, :contact_name, :delivery_location, length: { maximum: 200 }
    validates :organisation_number, format: { with: /\A\d{9}\z/ }
    validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :contact_phone, length: { maximum: 40 }, allow_blank: true
    validates :requested_items, length: { maximum: 4_000 }
    validates :seller_response, length: { maximum: 6_000 }, allow_blank: true
    validates :status, inclusion: { in: STATUSES }
    validates :seller_response, presence: true, if: :responded?

    before_validation :normalize_business_details
    validate :store_must_be_wholesale, on: :create
    validate :buyer_must_not_own_store, on: :create

    scope :awaiting_response, -> { where(status: "submitted") }
    scope :recent, -> { order(created_at: :desc) }

    def submitted? = status == "submitted"
    def responded? = status == "responded"

    def send_response!(text)
      return false unless update(
        seller_response: text,
        status: "responded",
        responded_at: Time.current
      )

      notify_buyer!
      true
    end

    def notify_store_owner!
      owner_id = Marketplace::Store.where(id: store_id).pick(:owner_id)
      recipient = User.strict_loading(false).find_by(id: owner_id)
      return unless recipient

      deliver_notification(
        recipient,
        title: I18n.t("marketplace.wholesale_enquiries.notification_title"),
        body: I18n.t("marketplace.wholesale_enquiries.notification_body",
                     store: Marketplace::Store.where(id: store_id).pick(:name)),
        source: self,
        kind: "alert"
      )
    end

    private

    def normalize_business_details
      self.buyer_company_name = buyer_company_name.to_s.strip
      self.organisation_number = organisation_number.to_s.gsub(/[[:space:]-]/, "")
      self.contact_name = contact_name.to_s.strip
      self.contact_email = contact_email.to_s.strip.downcase
      self.contact_phone = contact_phone.to_s.strip.presence
      self.requested_items = requested_items.to_s.strip
      self.delivery_location = delivery_location.to_s.strip
      self.seller_response = seller_response.to_s.strip.presence
      self.status = "submitted" if status.blank?
    end

    def store_must_be_wholesale
      return if Marketplace::Store.where(id: store_id, vertical: "wholesale").exists?

      errors.add(:store, :invalid)
    end

    def buyer_must_not_own_store
      owner_id = Marketplace::Store.where(id: store_id).pick(:owner_id)
      errors.add(:buyer, :invalid) if owner_id.present? && owner_id == buyer_id
    end

    def notify_buyer!
      recipient = User.strict_loading(false).find_by(id: buyer_id)
      return unless recipient

      deliver_notification(
        recipient,
        title: I18n.t("marketplace.wholesale_enquiries.buyer_notification_title"),
        body: I18n.t("marketplace.wholesale_enquiries.buyer_notification_body"),
        source: self,
        kind: "alert"
      )
    end
  end
end
