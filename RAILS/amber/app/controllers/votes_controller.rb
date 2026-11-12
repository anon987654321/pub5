# frozen_string_literal: true

class VotesController < ApplicationController
  before_action :require_user_session

  def create
    @post = Post.find(params[:post_id])
    vote = @post.votes.find_or_initialize_by(user: Current.user)
    value = params.dig(:vote, :value).to_i

    if vote.persisted? && vote.value == value
      vote.destroy
    else
      vote.update!(value:)
    end

    # Vote updates the score with SQL; the controller's original post instance
    # still holds the old value. Reload before rendering only the vote rail.
    @post.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
    end
  end
end
