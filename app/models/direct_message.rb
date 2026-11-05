# Metadata for one-to-one DMs only: who sent a message and when. Message text is never stored.
class DirectMessage < ApplicationRecord
  HISTORY_WINDOW = 30.days

  belongs_to :x_sync_run, class_name: "X::SyncRun", optional: true
  validates :x_id, presence: true, uniqueness: true
  validates :conversation_x_id, :partner_x_id, :occurred_at, presence: true
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :source, inclusion: { in: %w[x_api archive] }

  # Returns :new, :known, or :skipped. Group and self conversations never establish a one-to-one exchange.
  def self.record!(x_id:, conversation_x_id:, participants:, sender_x_id:, occurred_at:, source:, run: nil)
    owner = Workspace.current.owner_x_id
    return :skipped unless participants.size == 2 && participants.count(owner) == 1
    partner = (participants - [owner]).first
    return :skipped unless [owner, partner].include?(sender_x_id)
    record = find_or_initialize_by(x_id: x_id)
    return :known if record.persisted?
    record.update!(conversation_x_id: conversation_x_id, partner_x_id: partner, source: source, x_sync_run: run,
      direction: sender_x_id == owner ? "outgoing" : "incoming", occurred_at: occurred_at)
    :new
  end

  def self.capture!(row, run:)
    record!(x_id: row.fetch("id"), conversation_x_id: row.fetch("conversation_id"), participants: row.fetch("conversation_id").split("-"),
      sender_x_id: row.fetch("sender_id"), occurred_at: Time.iso8601(row.fetch("created_at")), source: "x_api", run: run)
  end

  # API checks cover the 30 days before each check; a complete archive covers the account's whole life until it was generated.
  # Returns the start of the unbroken stretch that reaches the most recent check.
  def self.covered_since
    windows = X::SyncRun.where(dataset: "dm_events", status: "completed").pluck(:upper_bound).map { |checked| [checked - HISTORY_WINDOW, checked] }
    windows += X::ArchiveImport.where(partial: false).pluck(:account_created_at, :generated_at)
    merged = windows.sort_by(&:first).each_with_object([]) do |(from, to), stretches|
      if stretches.any? && from <= stretches.last.last
        stretches.last[1] = [stretches.last.last, to].max
      else
        stretches << [from, to]
      end
    end
    merged.max_by(&:last)&.first
  end
end
