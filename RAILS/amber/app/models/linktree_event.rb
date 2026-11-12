# frozen_string_literal: true

# One counted moment on a public link-in-bio page: the page view or the link
# click. The visitor carries an anonymized hash, never an address; the
# click-to-paywall journey (page_view → link_click → gate) is the growth loop
# these rows measure.
class LinktreeEvent < ApplicationRecord
  EVENT_TYPES = %w[page_view link_click].freeze

  belongs_to :linktree_page
  belongs_to :linktree_link, optional: true

  validates :event_type, inclusion: { in: EVENT_TYPES }

  scope :views, -> { where(event_type: "page_view") }
  scope :clicks, -> { where(event_type: "link_click") }

  class << self
    # SHA-256 of the coarse visitor signature (IP-day-user-agent). The hash
    # counts unique visitors without holding anything that identifies one.
    def visitor_hash(request)
      coarse = [ request.remote_ip, Time.current.strftime("%Y%m%d"), request.user_agent ].join("|")
      Digest::SHA256.hexdigest(coarse)
    end
  end
end
