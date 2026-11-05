class Outreach < ApplicationRecord
  include WorkspaceScoped
  belongs_to :reply_event
  belongs_to :daily_session, optional: true
  validates :target_x_id, presence: true, uniqueness: { scope: :workspace_id }
end
