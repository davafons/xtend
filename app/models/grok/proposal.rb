# Profile facts, recaps, and tags that Grok Bot proposed for a person. Nothing applies until the owner accepts it.
class Grok::Proposal < ApplicationRecord
  include WorkspaceScoped
  KINDS = %w[profile recap tags].freeze
  belongs_to :person
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: %w[pending accepted dismissed] }
  validates :via, inclusion: { in: %w[mcp paste] }

  scope :pending, -> { where(status: "pending") }

  def self.latest_recap
    where(kind: "recap", status: "accepted").order(reviewed_at: :desc).first
  end

  # Accepted profile facts only fill empty fields, so X-collected data and owner edits always win.
  def accept!
    transaction do
      person.fill_blank_profile!(payload.slice(*Grok::Intake::PROFILE_FIELDS)) if kind == "profile"
      person.add_tags!(payload["tags"], source: "grok") if kind == "tags"
      update!(status: "accepted", reviewed_at: Time.current)
    end
  end

  def dismiss!
    update!(status: "dismissed", reviewed_at: Time.current)
  end
end
