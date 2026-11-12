# frozen_string_literal: true

# The engine-local helper is required because isolated engines do not fold it
# into controllers inheriting the host ApplicationController.
class Playlist::BaseController < Shared::SluggedVerticalController
  helper PlaylistHelper
end
