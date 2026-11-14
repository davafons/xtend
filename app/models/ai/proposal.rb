# A change an AI assistant made or proposed for a person: profile facts, a recap, tags, a note, or a reminder.
#
# With the workspace's "AI applies changes" setting on, a change from the connector applies at once (status
# "applied") and records in `applied` exactly what it changed, so undo! reverses only that and leaves anything the
# owner changed since. With it off, or for pasted results, it waits as "pending" until the owner accepts it.
# Either way it only touches Xtend's own records: nothing here reaches X.
class AI::Proposal < ApplicationRecord
  include WorkspaceScoped
  KINDS = %w[profile recap tags note reminder].freeze
  STATUSES = %w[pending accepted applied dismissed undone].freeze
  LABELS = { "profile" => "Profile facts", "recap" => "Recap", "tags" => "Tags", "note" => "Note", "reminder" => "Reminder" }.freeze
  belongs_to :person
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :via, inclusion: { in: %w[mcp paste] }

  scope :pending, -> { where(status: "pending") }
  scope :applied, -> { where(status: "applied") }
  scope :in_effect, -> { where(status: %w[accepted applied]) }

  def self.latest_recap
    in_effect.where(kind: "recap").order(reviewed_at: :desc).first
  end

  def label = LABELS.fetch(kind)
  def undoable? = status.in?(%w[accepted applied])

  def accept!
    apply_change!("accepted")
  end

  # Applies a change from a connected assistant without review.
  def apply!
    apply_change!("applied")
  end

  def dismiss!
    update!(status: "dismissed", reviewed_at: Time.current)
  end

  # Reverses what this change did, as far as it is still there: tags it added, profile fields it filled that still
  # hold its value, the note text it appended, the reminder it created unless already done.
  def undo!
    raise ArgumentError, "Only an applied or accepted change can be undone." unless undoable?
    transaction do
      case kind
      when "tags"
        person.person_tags.joins(:tag).where(tags: { name: applied["tags"] }, source: "ai").destroy_all
      when "profile"
        restore = applied.fetch("fields", {}).select { |key, value| person[key].to_s == value.to_s }
        person.update!(restore.transform_values { nil }) if restore.any?
      when "note"
        text = applied["text"].to_s
        person.update!(notes: person.notes.to_s.sub(text, "").strip.presence) if text.present? && person.notes.to_s.include?(text)
      when "reminder"
        Reminder.open.find_by(id: applied["reminder_id"], person: person)&.destroy!
      end
      update!(status: "undone", undone_at: Time.current)
    end
  end

  private

  def apply_change!(new_status)
    transaction do
      record = case kind
      when "profile"
        fields = payload.slice(*AI::Intake::PROFILE_FIELDS).select { |key, value| value.present? && person[key].blank? }
        person.update!(fields) if fields.any?
        { "fields" => fields }
      when "tags"
        { "tags" => person.add_tags!(payload["tags"], source: "ai").map(&:name) }
      when "note"
        text = "AI, #{Date.current.strftime('%-d %b %Y')}: #{payload['text']}"
        person.update!(notes: [ person.notes.presence, text ].compact.join("\n\n"))
        { "text" => text }
      when "reminder"
        reminder = person.reminders.create!(reason: payload["reason"], due_on: Date.iso8601(payload["due_on"]))
        { "reminder_id" => reminder.id }
      else
        {}
      end
      update!(status: new_status, reviewed_at: Time.current, applied: record)
    end
  end
end
