# frozen_string_literal: true

# Keep the Takeaway namespace and compatibility mount while sharing slug lookup.
class Takeaway::BaseController < Shared::SluggedVerticalController
end
