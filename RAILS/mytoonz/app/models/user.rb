# frozen_string_literal: true

class User < ApplicationRecord
  include Shared::Notifiable
  include Shared::Reactable
  include Shared::GeoLocatable

  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :comic_strips, dependent: :destroy

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
end
