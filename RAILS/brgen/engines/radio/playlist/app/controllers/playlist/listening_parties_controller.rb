# frozen_string_literal: true

class Playlist::ListeningPartiesController < Playlist::BaseController
    before_action :require_user_session
    before_action :set_set
    before_action :set_party,     only: %i[show update destroy]
    before_action :require_host!, only: %i[update destroy]

    def show
      unless party_viewer_allowed?
        redirect_to set_path(@set), alert: t("flash.playlist.party_code_required")
        return
      end
      @messages = @party.party_messages.includes(:user).chronological.limit(100)
      @tracks = shareable_tracks
    end

    def create
      unless set_owner_or_editor?
        redirect_to set_path(@set), alert: t("shared.flash.not_authorized")
        return
      end
      @party = @set.build_listening_party(host: Current.user, status: "active")
      first_track = shareable_tracks.first
      @party.current_track = first_track
      @party.save!
      redirect_to set_listening_party_path(@set), notice: t("flash.playlist.party_started")
    end

    def update
      track_id = params[:track_id].presence || @party.current_track_id
      track = shareable_tracks.find { |candidate| candidate.id.to_s == track_id.to_s }
      return head :unprocessable_entity if track_id.present? && !track

      @party.sync!(track: track, position_seconds: params[:position_seconds],
                   playing: params[:playing].to_s != "false")
      head :ok
    end

    def destroy
      @party.end!
      redirect_to set_path(@set), notice: t("flash.playlist.party_ended")
    end

    private

    def shareable_tracks
      @set.tracks.order(:position).select { |track| track.playable_by?(nil) }
    end

    def set_set
      party = { listening_party: { current_track: :audio_file_attachment } }
      @set = Playlist::Set.includes(party, :tracks).find(params[:set_id])
      raise ActiveRecord::RecordNotFound unless set_visible_to_viewer?
    end

    def set_visible_to_viewer?
      case @set.privacy.to_s
      when "", "public", "unlisted" then true
      # Anything not named public is private: a privacy value outside the list
      # reached the database some way other than the form, and a typo must not
      # publish a set its owner hid.
      else
        Current.user && (
          @set.user_id == Current.user.id ||
          @set.collaborations.exists?(user_id: Current.user.id)
        )
      end
    end

    def set_owner_or_editor?
      Current.user && (
        @set.user_id == Current.user.id ||
        @set.collaborations.exists?(user_id: Current.user.id, role: %w[owner editor])
      )
    end

    def set_party
      @party = @set.listening_party || raise(ActiveRecord::RecordNotFound)
    end

    def require_host!
      unless Current.user && @party.host_id == Current.user.id
        redirect_to(set_listening_party_path(@set), alert: t("shared.flash.not_authorized"))
      end
    end

    def party_viewer_allowed?
      return true if Current.user && @party.host_id == Current.user.id
      return true if Array(session[:listening_party_ok]).include?(@party.id)

      code = params[:code].to_s.upcase
      return false unless code.present? && code == @party.join_code.to_s.upcase

      session[:listening_party_ok] = Array(session[:listening_party_ok]) | [ @party.id ]
      true
    end
end
