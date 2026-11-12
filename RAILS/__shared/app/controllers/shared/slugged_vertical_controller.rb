# frozen_string_literal: true

module Shared
  # Common parent for vertical controllers whose public records use slug URLs
  # while older numeric links remain supported. Keep vertical-specific helpers,
  # callbacks and product policy in each engine's own base controller.
  class SluggedVerticalController < ApplicationController
    include Shared::FindableBySlug
  end
end
