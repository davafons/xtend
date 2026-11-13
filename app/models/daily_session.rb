class DailySession < ApplicationRecord
  include WorkspaceScoped
  TARGET = 20
  has_many :outreaches, dependent: :nullify

  def self.current
    where(completed_at: nil).order(:created_at).first || where(completed_at: Date.current.all_day).order(completed_at: :desc).first || create!(anchor_day: Date.current)
  rescue ActiveRecord::RecordNotUnique
    find_by!(completed_at: nil)
  end

  def progress
    outreaches.count
  end

  def remaining
    [ TARGET - progress, 0 ].max
  end

  # Your replies inside exchanges you were already in, since the session began. They never count toward the target.
  def follow_ups
    ReplyEvent.where(direction: "outgoing", classification: "continuation", occurred_at: anchor_day.in_time_zone..).count
  end

  def targets
    outreaches.includes(reply_event: :person).order(:created_at)
  end

  def percent
    [ (progress.to_f / TARGET * 100).round, 100 ].min
  end

  def complete!
    raise ActiveRecord::RecordInvalid, self if progress < TARGET
    update!(completed_at: Time.current)
  end
end
