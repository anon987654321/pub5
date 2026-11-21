# frozen_string_literal: true

# One city-scoped query contract for every vertical that consumes Places.
# A missing city is always an empty relation; rejected records never leak into
# public maps or storefront selectors. Verification is opt-in so existing
# manually curated records continue to work while imports are being reviewed.
class PlaceDirectory
  class << self
    def for_city(city, verified_only: false, kinds: nil)
      return Place.none unless city&.id

      scope = Place.where(city_id: city.id).not_rejected
      scope = scope.verified if verified_only
      selected_kinds = Array(kinds).compact_blank
      scope = scope.where(kind: selected_kinds) if selected_kinds.any?
      scope
    end

    def find_external(city:, source:, external_id:)
      return Place.none unless city&.id && source.present? && external_id.present?

      for_city(city).where(source:, external_id:)
    end
  end
end
