# frozen_string_literal: true

class ImportRun < ApplicationRecord
  belongs_to :platform

  STATUSES = %w[running succeeded failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc, id: :desc) }

  # The published binary package index contains names and versions only.
  # Its URL is recorded as source_revision by Ports::Importer; it must not be
  # presented as a full ports-tree metadata refresh.
  def package_index_only?
    source_revision.to_s.match?(%r{/packages/[^/]+/index\.txt\z})
  end

  def mark_succeeded!(ports_count:, source_revision: nil)
    update!(
      status: "succeeded",
      finished_at: Time.current,
      ports_count: ports_count,
      source_revision: source_revision
    )
  end

  def mark_failed!(error_message)
    update!(status: "failed", finished_at: Time.current, error_message: error_message)
  end
end
