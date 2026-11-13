# A post you replied to for the first time. Each target counts once, toward the session it happened in;
# replies inside an exchange you were already in never count.
class Outreach::Target < ApplicationRecord
  include WorkspaceScoped
  belongs_to :reply_event
  belongs_to :session, class_name: "Outreach::Session", foreign_key: :outreach_session_id, optional: true
  validates :target_x_id, presence: true, uniqueness: { scope: :workspace_id }

  # Replies collected as history (outreach_eligible false) or from before the session began are remembered
  # as targets, so they can't count again, but they don't add to any session.
  def self.record!(event)
    session = Outreach::Session.current if event.outreach_eligible
    find_or_create_by!(target_x_id: event.target_x_id) do |target|
      target.reply_event = event
      target.session = session if session && event.occurred_at >= session.started_at
    end
  end
end
