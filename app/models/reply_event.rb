class ReplyEvent < ApplicationRecord
  include WorkspaceScoped
  belongs_to :person
  has_one :outreach_target, class_name: "Outreach::Target", dependent: :destroy

  validates :x_id, presence: true, uniqueness: { scope: :workspace_id }
  validates :target_x_id, :occurred_at, :confirmed_at, presence: true
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :classification, inclusion: { in: %w[initial continuation unclassified] }
  validates :source, inclusion: { in: %w[x_api x_capture archive demo] }
  validate :known_external_person

  def self.ingest_verified!(profile:, **attributes)
    transaction do
      person = Person.resolve_profile!(profile)
      event = find_or_initialize_by(x_id: attributes.fetch(:x_id))
      if event.persisted? && [event.person_id, event.target_x_id, event.direction] != [person.id, attributes.fetch(:target_x_id), attributes.fetch(:direction)]
        raise ArgumentError, "A confirmed reply ID cannot be reassigned to another interaction."
      end
      if event.persisted?
        incoming_class = attributes.fetch(:classification)
        if event.classification != "unclassified" && incoming_class != "unclassified" && event.classification != incoming_class && !(event.classification == "initial" && incoming_class == "continuation")
          raise ArgumentError, "Confirmed reply classification cannot be reassigned."
        end
        attributes[:classification] = event.classification if incoming_class == "unclassified"
        attributes[:outreach_eligible] = event.outreach_eligible
      end
      event.assign_attributes(attributes.merge(person: person))
      event.save!
      if event.direction == "outgoing" && event.classification == "initial"
        Outreach::Target.record!(event)
      elsif event.classification == "continuation"
        event.outreach_target&.destroy!
      end
      event
    end
  end

  private

  def known_external_person
    owner = Current.workspace.owner_x_id
    errors.add(:person, "needs an identified workspace account") if owner.blank?
    errors.add(:person, "cannot be your own account") if owner.present? && person&.x_id == owner
    errors.add(:occurred_at, "cannot be in the future") if occurred_at && occurred_at > Time.current
  end
end
