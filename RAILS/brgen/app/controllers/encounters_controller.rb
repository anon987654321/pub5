# frozen_string_literal: true

# Chatroulette-style random pairing on the ambient-chat machinery. A stranger
# chat needs both sides to ask for a stranger, so guests play without an
# account - the ask is the consent, the same Craigslist shape the geo rooms use.
class EncountersController < ApplicationController
  # Anonymous stranger chat is abuse-prone - cap how fast encounters start,
  # the same rule nearby applies to its stranger chats.
  rate_limit to: 10, within: 5.minutes, only: :create,
    with: -> { redirect_to nearby_path, alert: t("flash.encounters_rate_limited") }
  before_action :require_an_ask, only: :waiting

  def create
    me = ensure_guest_user!
    blocked = me.blocked_user_ids + Block.where(blocked_id: me.id).pluck(:blocker_id)
    mine = Encounter.pair!(me, blocked_ids: blocked.uniq)
    if mine.matched?
      redirect_to mine.chat
    else
      redirect_to waiting_encounters_path
    end
  end

  # The waiting page leans on the shared morph refresh: every couple of
  # seconds the refresh visit lands here, and the moment the pairing exists
  # the visit follows the redirect into the conversation.
  def waiting
    encounters = Current.user.encounters
    matched = encounters.matched.order(:updated_at).last
    if matched&.chat && matched.fresh?
      matched.close!
      return redirect_to(matched.chat)
    end

    # Re-arm a lapsed wait so a stranger arriving later can still pair.
    encounters.waiting.first_or_create!
    render :waiting
  end

  def destroy
    Current.user.encounters.waiting.update_all(status: Encounter::CLOSED)
    redirect_to nearby_path, notice: t("flash.encounter_left")
  end

  private

  # Only someone who asked waits. A visitor with no encounter (a crawler, the
  # deploy canary, a stale link) got an unsaved guest whose re-armed wait
  # failed validation and answered 422.
  def require_an_ask
    me = Current.user
    redirect_to(nearby_path) unless me&.persisted? && me.encounters.exists?
  end
end
