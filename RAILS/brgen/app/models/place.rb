# frozen_string_literal: true

class Place < ApplicationRecord
  include Shared::ActivityTrackable
  include Shared::GeoLocatable
  include Shared::MediaProcessable
  # Not CityTenantable: places.city_id is NOT NULL and belongs_to :city is
  # required here, so the optional-tenant declaration would weaken it and add a
  # default_scope to five existing query sites. The scope alone is what the
  # city-facing surfaces need.
  include CityScoped
  belongs_to :city
  belongs_to :neighborhood, optional: true

  has_one_attached :photo
  process_media_variants :photo, variants: {
    card: { resize_to_limit: [ 720, 480 ], format: :webp },
    thumb: { resize_to_limit: [ 320, 240 ], format: :webp },
  }

  validates :kind, presence: true
  # The map drops a point outside these ranges without a word, so a swapped or
  # mistyped coordinate has to be refused when it is saved.
  validates :latitude, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :name, presence: true

  SOURCES = %w[brgen openstreetmap operator].freeze
  VERIFICATION_STATES = %w[unverified verified rejected].freeze
  LOCATION_PRECISIONS = %w[exact street neighbourhood city].freeze

  before_validation { self.external_id = external_id.presence }
  validates :source, inclusion: { in: SOURCES }
  validates :verification_state, inclusion: { in: VERIFICATION_STATES }
  validates :location_precision, inclusion: { in: LOCATION_PRECISIONS }
  validates :external_id, uniqueness: { scope: [ :city_id, :source ] }, allow_nil: true

  scope :not_rejected, -> { where.not(verification_state: "rejected") }
  scope :verified, -> { where(verification_state: "verified") }

  # Stable source identity for imports; native Brgen-created places retain their
  # database id without pretending it is an upstream provider identifier.
  def stable_key
    external_id.present? ? "#{source}:#{external_id}" : "brgen:#{id}"
  end

  # Public map coordinates respect the precision policy stored with each place.
  # Existing hand-entered records default to exact; imported or sensitive records
  # can be rounded to street, neighbourhood or city scale without changing the
  # private canonical coordinates used for operations.
  def public_coordinates
    digits = { "exact" => 6, "street" => 4, "neighbourhood" => 3, "city" => 2 }
      .fetch(location_precision, 2)
    [ latitude.to_f.round(digits), longitude.to_f.round(digits) ]
  end

  has_many :place_check_ins, dependent: :destroy
  has_many :check_in_users, through: :place_check_ins, source: :user
  has_many :restaurants, class_name: "Takeaway::Restaurant", dependent: :nullify
  has_many :stores, class_name: "Marketplace::Store", dependent: :nullify
end
