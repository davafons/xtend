# Something to do about a person on a day you chose, such as "ask how the launch went". Reminders are the
# owner's own: nothing creates them automatically, and they never send anything anywhere.
class Reminder < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person

  REASON_LENGTH = 200

  validates :reason, presence: true, length: { maximum: REASON_LENGTH }
  validates :due_on, presence: true

  scope :open, -> { where(completed_at: nil) }
  scope :due, -> { open.where(due_on: ..Date.current) }
  scope :upcoming, -> { open.where(due_on: Date.current.tomorrow..) }

  def due?
    completed_at.nil? && due_on <= Date.current
  end

  def complete!
    update!(completed_at: Time.current)
  end
end
