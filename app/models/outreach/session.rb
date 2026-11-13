# A dedicated reply session and its progress toward TARGET distinct new posts. It runs past midnight while
# you're still replying and ends on its own once it goes quiet, so the next reply starts a fresh one.
class Outreach::Session < ApplicationRecord
  include WorkspaceScoped
  TARGET = 20
  QUIET_AFTER = 8.hours
  has_many :targets, class_name: "Outreach::Target", foreign_key: :outreach_session_id, dependent: :nullify

  def self.current
    latest = order(:anchor_day).last
    return latest if latest && (latest.anchor_day == Date.current || latest.active_since?(QUIET_AFTER.ago))
    create!(anchor_day: Date.current)
  rescue ActiveRecord::RecordNotUnique
    find_by!(anchor_day: Date.current)
  end

  def started_at = anchor_day.in_time_zone

  def active_since?(time)
    targets.joins(:reply_event).where(reply_events: { occurred_at: time.. }).exists?
  end

  def progress
    targets.count
  end

  def remaining
    [ TARGET - progress, 0 ].max
  end

  # Your replies inside exchanges you were already in, since the session began. They never count toward the target.
  def follow_ups
    ReplyEvent.where(direction: "outgoing", classification: "continuation", occurred_at: started_at..).count
  end
end
