class Outreach < ApplicationRecord
  belongs_to :reply_event
  belongs_to :daily_session, optional: true
  validates :target_x_id, presence: true, uniqueness: true
end
