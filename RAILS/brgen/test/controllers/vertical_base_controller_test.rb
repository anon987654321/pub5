# frozen_string_literal: true

require "test_helper"

class VerticalBaseControllerTest < ActionDispatch::IntegrationTest
  test "slugged verticals share the common controller base" do
    [
      Marketplace::BaseController,
      Takeaway::BaseController,
      Tv::BaseController,
      Playlist::BaseController,
    ].each do |controller|
      assert_operator controller, :<, Shared::SluggedVerticalController
    end
  end

  test "shared base remains attached to the host application controller" do
    assert_equal ApplicationController, Shared::SluggedVerticalController.superclass
  end

  test "playlist keeps its isolated engine helper" do
    assert_includes Playlist::BaseController._helpers.ancestors, PlaylistHelper
  end

  test "dating and maps retain their own controller policies" do
    refute_operator Dating::BaseController, :<, Shared::SluggedVerticalController
    refute_operator Maps::BaseController, :<, Shared::SluggedVerticalController
    assert_includes Dating::BaseController.private_instance_methods(true).map(&:to_sym),
                    :candidate_scope
    assert_includes Maps::BaseController.private_instance_methods(true).map(&:to_sym),
                    :places_in_current_city
  end
end
