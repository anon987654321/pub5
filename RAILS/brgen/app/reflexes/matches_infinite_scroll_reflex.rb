# frozen_string_literal: true

class MatchesInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "dating/matches/match", as: :match

  private

  def scope
    Dating::Match.active.visible_to(Current.user)
      .includes(initiator: { dating_profile: { photos_attachments: :blob } },
                receiver: { dating_profile: { photos_attachments: :blob } })
      .order(created_at: :desc, id: :desc)
  end
end
