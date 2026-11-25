# frozen_string_literal: true

require "openssl"
require "json"
require "base64"

module Shared
  class ReferralSplinter < ApplicationRecord
    self.table_name = "referral_splinters"
    VERTICALS = %w[playlist dating].freeze
    REWARD_DAYS = 30
    TOKEN_PREFIX = "splinter_"
    TOKEN_TTL = 30.days

    belongs_to :referrer, class_name: "::User"
    belongs_to :redeemed_by, class_name: "::User", optional: true
    has_one :credit, class_name: "Shared::ReferralCredit", dependent: :restrict_with_exception
    validates :vertical, inclusion: { in: VERTICALS }
    validates :reward_tier, inclusion: { in: VERTICALS.map { |name| "#{name}_pro_30_days" } }

    # The referring account without a lazy read on a locked, strict splinter.
    def referrer_account = strict_safe(:referrer)

    class << self
      def generate!(referrer:, vertical:, validity: TOKEN_TTL)
        vertical = vertical.to_s
        raise ArgumentError, "unsupported referral vertical" unless VERTICALS.include?(vertical)
        raise ArgumentError, "referrer must be a real account" if referrer.guest? || referrer.deleted_at.present?

        expires_at = Time.current + validity
        reward_tier = "#{vertical}_pro_30_days"
        payload = { ref: referrer.id, vertical:, tier: reward_tier, exp: expires_at.to_i,
                    nonce: SecureRandom.hex(12) }
        token = "#{TOKEN_PREFIX}#{encrypt(payload)}"
        create!(referrer:, vertical:, reward_tier:, token_digest: digest(token), expires_at:)
        token
      end

      def redeem!(token:, user:)
        raise ArgumentError, "a real account is required" if user.guest? || user.deleted_at.present?
        payload = decrypt(token.to_s.delete_prefix(TOKEN_PREFIX))
        raise ArgumentError, "referral link has expired" if Time.current.to_i >= Integer(payload.fetch(:exp))
        vertical = payload.fetch(:vertical).to_s
        raise ArgumentError, "unsupported referral vertical" unless VERTICALS.include?(vertical)

        transaction do
          splinter = lock.find_by!(token_digest: digest(token))
          raise ArgumentError, "referral link has expired" if splinter.expires_at <= Time.current
          raise ArgumentError, "referral cannot be redeemed by its creator" if splinter.referrer_id == user.id
          raise ArgumentError, "referral was already redeemed" if splinter.redeemed_at?
          raise ArgumentError, "account has already redeemed a referral" if where(redeemed_by_id: user.id).exists?
          raise ArgumentError, "referral token does not match its record" unless
            splinter.referrer_id == Integer(payload.fetch(:ref)) &&
            splinter.vertical == vertical && splinter.reward_tier == payload.fetch(:tier).to_s

          splinter.update!(redeemed_by: user, redeemed_at: Time.current)
          grant_credit!(splinter, vertical)
          splinter
        end
      rescue KeyError, TypeError, ArgumentError, ActiveRecord::RecordNotFound,
             ActiveRecord::RecordNotUnique, OpenSSL::Cipher::CipherError
        raise ArgumentError, "referral token is invalid, expired, or already used"
      end

      private

      # The referrer's credit extends any unexpired one for the same entitlement.
      def grant_credit!(splinter, vertical)
        now = Time.current
        entitlement = "#{vertical}_pro"
        referrer = splinter.referrer_account
        current_expiry = ReferralCredit.where(user: referrer, entitlement:, expires_at: now..).maximum(:expires_at)
        ReferralCredit.create!(user: referrer, referral_splinter: splinter, vertical:, entitlement:,
                               expires_at: [current_expiry, now].compact.max + REWARD_DAYS.days)
      end

      def encrypt(payload)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = encryption_key
        iv = cipher.random_iv
        ciphertext = cipher.update(JSON.generate(payload)) + cipher.final
        [iv, cipher.auth_tag, ciphertext].map { |part| Base64.urlsafe_encode64(part, padding: false) }.join(".")
      end

      def decrypt(token)
        iv_part, tag_part, ciphertext_part, extra = token.split(".", 4)
        raise ArgumentError, "malformed token" if [iv_part, tag_part, ciphertext_part].any?(&:blank?) || extra

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = encryption_key
        cipher.iv = Base64.urlsafe_decode64(iv_part)
        cipher.auth_tag = Base64.urlsafe_decode64(tag_part)
        JSON.parse(cipher.update(Base64.urlsafe_decode64(ciphertext_part)) + cipher.final, symbolize_names: true)
      end

      def encryption_key
        Rails.application.key_generator.generate_key("brgen/referral-splinter/v1", 32)
      end

      def digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
    end
  end
end
