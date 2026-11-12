# frozen_string_literal: true

class RestaurantsInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "takeaway/restaurants/card", as: :restaurant

  private

  def scope
    scope = Takeaway::Restaurant.publicly_visible.includes(:user)
    @sort = Takeaway::Restaurant::SORTS.include?(element.dataset["sort"].to_s) ? element.dataset["sort"].to_s : "popular"
    scope = scope.where(cuisine_type: element.dataset["cuisine"]) if element.dataset["cuisine"].present?
    if element.dataset["q"].present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(element.dataset["q"])}%"
      scope = scope.where(
        "name LIKE ? OR city LIKE ? OR cuisine_type LIKE ? OR description LIKE ?",
        term, term, term, term
      )
    end
    scope.merge(Takeaway::Restaurant.sorted(@sort))
  end
end
