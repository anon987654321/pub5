# frozen_string_literal: true

# Compact style, like every other controller in this directory, and not
# `module Playlist; class ...`. Inside that nesting the constant `Playlist`
# resolves to the Playlist::Playlist *model* first, so `Playlist::Set` became
# `Playlist::Playlist::Set` and both index actions raised NameError.
class Playlist::HostedTracksController < Playlist::BaseController
  allow_unauthenticated_access only: %i[index show]
  before_action :require_real_user, except: %i[index show]
  before_action :set_track, only: %i[show edit update destroy]
  before_action :authorize_owner!, only: %i[edit update destroy]

  def index
    @mine = authenticated? && params[:mine] == "1"
    scope = @mine ? Playlist::Track.where(user_id: Current.user.id) : Playlist::Track.publicly_visible.unexpired
    scope = scope.where(users: { city_id: Current.city_record.id }) if !@mine && Current.city_record
    @query = params[:q].to_s.strip.first(100)
    @genre = params[:genre].to_s.strip.first(80)
    @creator = params[:creator].to_s.match?(/\A\d+\z/) ? params[:creator] : nil
    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope = scope.where("playlist_tracks.title LIKE :q OR playlist_tracks.artist LIKE :q OR playlist_tracks.album LIKE :q", q: pattern)
    end
    scope = scope.where("LOWER(playlist_tracks.genre) = ?", @genre.downcase) if @genre.present?
    scope = scope.where(user_id: @creator) if @creator
    @pagy, @tracks = pagy(scope.recent.includes(:user, artwork_attachment: { blob: :variant_records }))
  end

  def show
    @comments = @track.timestamped_comments.chronological.limit(200)
    @versions = @track.audio_versions.with_attached_audio_file.recent.limit(30) if Current.user&.id == @track.user_id
  end

  def new
    @track = Playlist::Track.new
  end

  def create
    files = Array(params.dig(:track, :audio_file)).compact
    if files.size > 1
      saved, failed = files.map { |file| [ file, build_upload(file) ] }.partition { |_file, track| track.save }
      flash[:alert] = upload_failures(failed) if failed.any?
      redirect_to hosted_tracks_path, notice: t("playlist.tracks_uploaded", count: saved.size)
    else
      @track = Playlist::Track.new(track_params.except(:audio_file))
      @track.user = Current.user if @track.respond_to?(:user=)
      @track.audio_file.attach(files.first) if files.any?
      @track.artwork.attach(params[:track][:artwork]) if params.dig(:track, :artwork).present?

      if @track.save
        redirect_to hosted_track_path(@track), notice: t("playlist.track_created")
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
  end

  def update
    @track.assign_attributes(track_params.except(:audio_file))
    return render :edit, status: :unprocessable_entity unless @track.valid?

    # Validated first and written together: a rejected title used to have
    # already swapped the audio and left an audio_version row behind.
    replacement = params.dig(:track, :audio_file).presence
    if (version_id = params.dig(:track, :restore_version_id).presence)
      version = @track.audio_versions.with_attached_audio_file.find(version_id)
      return head :unprocessable_entity unless version.audio_file.attached? && replacement.blank?

      replacement = version.audio_file.blob
    end
    Playlist::Track.transaction do
      @track.replace_audio!(replacement, actor: Current.user) if replacement
      @track.artwork.attach(params[:track][:artwork]) if params.dig(:track, :artwork).present?
      @track.save!
    end

    redirect_to hosted_track_path(@track), notice: t("playlist.track_updated")
  end

  def destroy
    @track.destroy
    redirect_to hosted_tracks_path(mine: "1"), notice: t("playlist.track_deleted")
  end

  private

  def set_track
    @track = Playlist::Track.includes(:user, audio_file_attachment: :blob, artwork_attachment: :blob).find(params[:id])
    return if track_visible_to_viewer?

    raise ActiveRecord::RecordNotFound
  end

  def track_visible_to_viewer?
    return true if Current.user && @track.user_id == Current.user.id

    @track.playable_by?(Current.user, direct_link: true)
  end

  def build_upload(file)
    track = Playlist::Track.new(track_params.except(:audio_file))
    track.user = Current.user
    track.audio_file.attach(file)
    track
  end

  # Names each file that did not save and why, so a bulk upload never drops
  # one in silence.
  def upload_failures(failed)
    reasons = failed.map do |file, track|
      name = file.try(:original_filename) || file.to_s
      "#{name}: #{track.errors.full_messages.to_sentence}"
    end
    t("playlist.tracks_not_uploaded", count: failed.size, files: reasons.join("; "))
  end

  def track_params
    params.require(:track).permit(:title, :artist, :album, :duration_seconds, :source_type, :source_url, :genre, :privacy, :expires_at)
  end

  # user_id, not user. set_track finds the record with nothing preloaded, and
  # ApplicationRecord sets strict_loading_by_default in every environment, so
  # reading the association raised before the comparison could run — the guard
  # never denied anyone, it failed for everyone, the owner included.
  #
  # The respond_to?(:user) line above it was the tell: a defence placed against
  # a failure that cannot happen, one line above the one that does. respond_to?
  # is true; the read is what raises. Comparing the column needs no preload and
  # cannot raise at all.
  def authorize_owner!
    return if Current.user && @track.user_id == Current.user.id

    redirect_to hosted_tracks_path, alert: t("shared.flash.not_authorized")
  end
end
