# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Shared::CableIdentity

    private

    # Amber's ambient chat widget renders for a soft guest with the guest's
    # own message stream (layouts/application.html.erb: "A guest carries a
    # soft identity, the widget frame loads the messages widget, and
    # messaging works without an account"). The HTTP side builds that guest
    # and remembers its id in session[:guest_user_id]
    # (Shared::Authentication#find_or_create_guest_user), but the cable side
    # only looked for a signed Session row - so the widget's
    # turbo-cable-stream-source sat permanently disconnected for exactly the
    # visitor it was built for, and every guest system visit failed at
    # turbo's connect assertion.
    #
    # The soft guest is an identified connection, not an anonymous one:
    # allow_anonymous_connection? keeps the shared default (false), so a
    # request with no session row AND no remembered guest is still refused.
    # Brgen's Connection carries the same override, plus a true anonymous
    # lane its public pages need and amber's do not.
    def set_current_user
      return true if super

      guest_id = request.session[:guest_user_id]
      return false unless guest_id

      guest = User.find_by(id: guest_id, guest: true)
      return false unless guest

      self.current_user = guest
      true
    end
  end
end
