class Follow::Snapshot < ApplicationRecord
  include WorkspaceScoped
  has_many :follow_memberships, class_name: "Follow::Membership", foreign_key: :follow_snapshot_id, dependent: :destroy
  has_many :people, through: :follow_memberships
  validates :direction, inclusion: { in: %w[followers following] }
  validates :source, :observed_at, presence: true

  def self.latest_complete(direction)
    where(direction: direction).where.not(completed_at: nil).order(observed_at: :desc).first
  end

  def self.latest(direction)
    where(direction: direction).order(observed_at: :desc, id: :desc).first
  end

  def fresh?
    completed_at.present? && observed_at >= 24.hours.ago
  end

  def person_ids
    follow_memberships.pluck(:person_id)
  end
end
